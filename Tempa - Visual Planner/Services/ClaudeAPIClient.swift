import Foundation
import Security
import CloudKit

struct TaskBreakdown: Codable, Sendable {
    struct Step: Codable, Sendable {
        let title: String
        let duration: Int
        let icon: String
        /// One of Cat.all's names, chosen by the model from what the step IS.
        /// Optional: the offline fallback and older responses don't carry it.
        var category: String? = nil

        /// The category to file the step under — the model's pick when it's
        /// a real one, otherwise derived from the icon (the icon vocabulary
        /// is shared, so it says a lot about the kind of action). Never
        /// silently "work": a cleaning step in work-blue was the bug.
        var resolvedCategory: String {
            if let category, Cat.all.contains(where: { $0.0 == category }) { return category }
            switch icon {
            case "laptopcomputer", "doc.text", "envelope": return "work"
            case "phone": return "social"
            case "bed.double", "book", "leaf": return "rest"
            case "figure.walk", "pills", "drop", "fork.knife", "shower": return "health"
            case "alarm", "trash", "sparkles", "hammer", "paintbrush": return "routine"
            default: return "personal"
            }
        }
    }

    /// Scheduling intent parsed from the user's words ("завтра о 3", "після роботи", …).
    /// The model always resolves a concrete `time`; we only shift it to a free slot
    /// when it's an approximate phrase (`precise == false`).
    struct Schedule: Codable, Sendable {
        let hasTime: Bool?     // user mentioned any time/day at all
        let precise: Bool?     // exact clock time → honor exactly; false → may shift to a free slot
        let date: String?      // "yyyy-MM-dd"
        let time: String?      // "HH:mm" 24h — always set when hasTime is true
    }

    let steps: [Step]
    let cleanTitle: String?
    let schedule: Schedule?

    init(steps: [Step], cleanTitle: String? = nil, schedule: Schedule? = nil) {
        self.steps = steps
        self.cleanTitle = cleanTitle
        self.schedule = schedule
    }
}

/// One task extracted from a spoken brain-dump ("plan my day").
struct PlannedTask: Codable, Sendable {
    let title: String
    let category: String?
    let durationMinutes: Int?
    let icon: String?      // SF Symbol fitting the task
    let hasTime: Bool?
    let precise: Bool?
    let date: String?      // "yyyy-MM-dd"
    let time: String?      // "HH:mm" 24h
    let times: [String]?   // several "HH:mm" per day, for things repeated daily (e.g. meds)
    let repeatDays: Int?   // repeat over N consecutive days from `date`
}

struct DayPlan: Codable, Sendable {
    let tasks: [PlannedTask]
}

/// A concrete offer Ask Tempa makes: one or more tasks, each phrased the way
/// the user would say it — time words included, because the day-plan parser
/// downstream is what turns them into scheduled blocks.
struct TaskProposal: Sendable {
    let toolUseId: String
    /// One short line, already in the user's language, shown as a chat bubble.
    let note: String
    let titles: [String]
}

/// One turn of an Ask Tempa conversation as the API sees it. The on-screen
/// greeting is UI-only and never becomes a turn — the API rejects a
/// conversation that opens on an assistant turn.
enum ChatTurn: Sendable {
    case user(String)
    /// The assistant turn exactly as the API returned it, kept as raw JSON.
    /// Thinking blocks carry signatures the API re-verifies when the turn is
    /// replayed alongside a tool result — rebuilding the turn from parsed
    /// pieces drops them and the next request is rejected.
    case assistant(rawContent: Data)
    /// Closes a tool call so the next request is a valid conversation.
    case proposalShown(toolUseId: String)
}

enum ChatReply: Sendable {
    case text(String)
    case proposal(TaskProposal)
}

/// What one Ask Tempa turn produced: the part worth showing, plus the raw
/// assistant turn to replay in the next request.
struct ChatResponse: Sendable {
    let reply: ChatReply
    let rawAssistantContent: Data
    /// Set whenever the turn contains a tool call — even one we couldn't use.
    /// The caller must close it, or the replayed turn has a tool_use with no
    /// result and every later request in the conversation is rejected.
    let pendingToolUseId: String?
}

enum ClaudeAPIError: Error, LocalizedError {
    case networkError(Error)
    case apiError(statusCode: Int, message: String)
    case parseError
    case noAPIKey
    case rateLimited
    case truncated

    var errorDescription: String? {
        switch self {
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .apiError(let code, let msg): return "API error \(code): \(msg)"
        case .parseError: return "Failed to parse AI response"
        case .noAPIKey: return "API key not configured"
        case .rateLimited: return "Daily limit reached"
        case .truncated: return "The reply was cut off"
        }
    }
}

final class ClaudeAPIClient: Sendable {
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-4-6"
    /// Ask Tempa reads the whole day and decides what to do first — judgement,
    /// not extraction, so it runs on a current-generation model rather than the
    /// one the extraction paths use. Thinking is on by default here, which is
    /// why max_tokens is generous below.
    private let chatModel = "claude-sonnet-5"
    private let keychainKey = "com.tempa.anthropic-api-key"

    /// One shared icon vocabulary for every AI-generated task — used by both the
    /// micro-step breakdown and the day-plan, so the icon logic is identical.
    static let iconVocabulary = "trash, sparkles, drop, fork.knife, bed.double, shower, bag, doc.text, envelope, phone, laptopcomputer, figure.walk, cart, pills, book, alarm, hammer, paintbrush, leaf"

    private let systemPrompt = """
    You are Tempa's task breakdown helper. You help adults with ADHD start \
    tasks they're avoiding by breaking them into tiny, concrete micro-steps.
    RULES:
    - Return 3 to 7 steps maximum. Never more.
    - Each step must be a concrete physical action, not abstract.
    - Each step needs an estimated duration in minutes (5-30 range).
    - Each step needs an SF Symbol icon name that fits the action.
    - Each step needs a "category" — exactly one of: work, personal, health, routine, \
    social, rest — chosen from what the step IS (wiping a counter is routine, a phone \
    call is social, a walk is health), not from the task's topic as a whole.
    - Tone: encouraging but not patronizing. Adult-to-adult.
    - LANGUAGE (most important): write "title" and "cleanTitle" in the SAME language as \
    the user's task text. The phrase examples further down are multilingual on purpose — \
    they exist so you can UNDERSTAND input in any language, and are NEVER a hint about \
    which language to answer in. JSON keys, "icon" values and all schedule values stay \
    exactly as specified — always English.
    - Output STRICT JSON only, no preamble, no markdown fences.

    SCHEDULE — figure out WHEN the user wants this, and always turn it into a concrete time.
    The user message begins with the current local datetime; resolve everything against it.
    Fill the "schedule" object:
    - "cleanTitle": the task with the time/date words removed (e.g. "cook dinner after \
    work" → "cook dinner"). If there were none, repeat the task as-is.
    - "hasTime": true if the user mentioned ANY time or day — including vague or colloquial \
    ones ("after work", "before bed", "tonight", "when I wake up", and the equivalents in \
    any other language). false only if nothing.
    - "date": the intended day as "yyyy-MM-dd". If a time is given with no day, use today.
    - "time": 24-hour "HH:mm" — your best concrete time for what they meant. ALWAYS set this \
    when hasTime is true. NEVER leave it null when there is any time hint.
    - "precise": true ONLY when the user stated an exact clock time ("at 3pm", "о 15:00", \
    "um halb zehn", "in 30 minutes"); false for approximate or contextual phrases.
    Map contextual phrases to concrete times. The user may write in ANY language; these \
    are recognition aids, not output language (defaults — use judgement):
    before work · перед роботою · vor der Arbeit · antes del trabajo · avant le travail → 07:30
    morning · вранці · зранку · morgens · früh · por la mañana · le matin · de manhã · \
    om morgenen · aamulla · 's ochtends → 08:00
    noon, lunchtime · опівдні · в обід · mittags · al mediodía · à midi · ao meio-dia · \
    lunsj · lounasaikaan · tussen de middag → 12:00
    afternoon · після обіду · вдень · nachmittags · por la tarde · l'après-midi · à tarde · \
    ettermiddag · iltapäivällä · 's middags → 14:00
    after work · після роботи · nach der Arbeit · después del trabajo · après le travail · \
    depois do trabalho · etter jobb · töiden jälkeen · na het werk → 18:00
    evening, tonight · ввечері · abends · por la noche · le soir · à noite · om kvelden · \
    illalla · 's avonds → 19:00
    before bed, at night · перед сном · на ніч · vor dem Schlafengehen · antes de dormir · \
    avant de dormir · før leggetid · ennen nukkumaanmenoa · voor het slapengaan → 22:00
    Days: tomorrow · завтра · morgen · mañana · demain · amanhã · i morgen · huomenna → \
    +1 day · the day after tomorrow · післязавтра · übermorgen → +2 days · a weekday name \
    in any language → that weekday's next date · "in N hours/minutes" → from now, precise=true.
    If an exact time with no day already passed today, use tomorrow.
    If the user mentioned NO time at all: hasTime=false, precise=false, date and time null.

    JSON shape:
    {
      "cleanTitle": "task without time words",
      "schedule": { "hasTime": true, "precise": false, "date": "2026-06-09", "time": "18:00" },
      "steps": [
        { "title": "...", "duration": 10, "icon": "trash", "category": "routine" }
      ]
    }
    Available icons (use only these SF Symbols): \(ClaudeAPIClient.iconVocabulary)
    """

    private let planSystemPrompt = """
    You are Tempa's day planner for an adult with ADHD. The user speaks a brain-dump of \
    several things to do, all in one go. Split it into SEPARATE tasks — one object per \
    distinct thing. NEVER merge two activities into one; NEVER split one activity into sub-steps.
    The user message begins with the current local datetime; resolve all times against it.
    For EACH task output:
    - "title": short, in the SAME language as the user's brain dump, with the time words \
    removed. The multilingual phrase examples below are recognition aids only — they never \
    decide the output language.
    - "category": exactly one of: work, personal, health, routine, social, rest.
    - "durationMinutes": a sensible estimate, 15–120.
    - "icon": one SF Symbol that fits the task, chosen ONLY from this list: \(ClaudeAPIClient.iconVocabulary).
    - "hasTime": true if a time or day was said for THIS task (including vague ones like \
    "after lunch", "tonight", in any language). false if no time hint for it.
    - "date": "yyyy-MM-dd" (today if a time but no day was given), else null.
    - "time": 24-hour "HH:mm" — your concrete time. Contextual defaults, any language: \
    morning/вранці/morgens/le matin 08:00, noon/в обід/mittags/à midi 12:00, afternoon/після \
    обіду/nachmittags/l'après-midi 14:00, after work/після роботи/nach der Arbeit 18:00, \
    evening/ввечері/abends/le soir 19:00, before bed/перед сном/vor dem Schlafengehen 22:00.
    - "precise": true only when an exact clock time was said ("at 3pm", "о 15:00", "um 9 Uhr").
    If a task has no time hint, set hasTime=false and date/time null — the app places it in order.

    RECURRENCE — for things that repeat (very common for meds/habits):
    - SEVERAL TIMES A DAY ("twice a day", "3 рази на день", "dreimal täglich", \
    "morning, noon and evening"): set "times" to the list of 24h "HH:mm" — e.g. ["08:00","13:00","19:00"]. \
    Use the same contextual mapping (зранку 08:00, обід 13:00, ввечері 19:00, перед сном 22:00). \
    Set hasTime=true and "time" to the first of them. If they only say a count ("3 рази") with \
    no parts of day, spread them across waking hours (e.g. 3× → 08:00, 14:00, 20:00).
    - OVER SEVERAL DAYS ("10 days in a row", "10 днів підряд", "eine Woche lang", "for a week"): \
    set "repeatDays" to that number of consecutive days (e.g. 10). "цей тиждень"/"this week" = 7. \
    "date" = the first day (today unless another start is given). Default repeatDays=1 (no repeat).
    - Output ONE task object with "times" and/or "repeatDays" — do NOT emit a separate object \
    per occurrence. Keep "title" clean of the count/frequency words ("Take the antibiotic").

    Keep the user's spoken order. Output STRICT JSON only, no markdown fences:
    { "tasks": [ { "title": "Take vitamin D", "category": "health", "durationMinutes": 5, "icon": "pills", "hasTime": true, "precise": false, "date": "2026-06-09", "time": "08:00", "times": ["08:00","14:00","20:00"], "repeatDays": 10 } ] }
    """

    /// Split a spoken brain-dump into several scheduled tasks ("plan my day").
    func planTasks(from brainDump: String) async throws -> DayPlan {
        var userContent = "\(Self.dateContextLine())\n\nBrain dump: \(brainDump)"
        if let directive = TaskLanguage.outputDirective(for: brainDump) {
            userContent += "\n\n\(directive)"
        }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1500,
            "system": [
                ["type": "text", "text": planSystemPrompt, "cache_control": ["type": "ephemeral"]]
            ],
            "messages": [["role": "user", "content": userContent]]
        ]

        let (data, http) = try await perform(body, beta: "prompt-caching-2024-07-31")
        guard http.statusCode == 200 else {
            let err = String(data: data, encoding: .utf8) ?? "Unknown"
            print("[Tempa] planTasks HTTP \(http.statusCode):", err)
            throw ClaudeAPIError.apiError(statusCode: http.statusCode, message: err)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let textBlock = content.first(where: { $0["type"] as? String == "text" }),
              let text = textBlock["text"] as? String else {
            throw ClaudeAPIError.parseError
        }
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = cleaned.data(using: .utf8) else { throw ClaudeAPIError.parseError }
        do {
            let plan = try JSONDecoder().decode(DayPlan.self, from: jsonData)
            #if DEBUG
            print("[Tempa] day plan → \(plan.tasks.count) tasks")
            #endif
            return plan
        } catch {
            print("[Tempa] planTasks decode error:", error, "\nraw:", cleaned)
            throw ClaudeAPIError.parseError
        }
    }

    func breakDown(task: String) async throws -> TaskBreakdown {
        var userContent = "\(Self.dateContextLine())\n\nTask: \(task)"
        if let directive = TaskLanguage.outputDirective(for: task) {
            userContent += "\n\n\(directive)"
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": [
                [
                    "type": "text",
                    "text": systemPrompt,
                    "cache_control": ["type": "ephemeral"]
                ]
            ],
            "messages": [
                ["role": "user", "content": userContent]
            ]
        ]

        let (data, httpResponse) = try await perform(body, beta: "prompt-caching-2024-07-31")

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            print("[Tempa] breakDown HTTP \(httpResponse.statusCode):", errorBody)
            throw ClaudeAPIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let textBlock = content.first(where: { $0["type"] as? String == "text" }),
              let text = textBlock["text"] as? String else {
            print("[Tempa] breakDown parse error: could not extract text block")
            throw ClaudeAPIError.parseError
        }

        let cleanedText = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleanedText.data(using: .utf8) else {
            throw ClaudeAPIError.parseError
        }

        do {
            let result = try JSONDecoder().decode(TaskBreakdown.self, from: jsonData)
            #if DEBUG
            if let s = result.schedule {
                print("[Tempa] schedule → hasTime=\(s.hasTime ?? false) precise=\(s.precise ?? false) date=\(s.date ?? "nil") time=\(s.time ?? "nil")")
            } else {
                print("[Tempa] schedule → (none returned)")
            }
            #endif
            return result
        } catch {
            print("[Tempa] breakDown decode error:", error, "\nraw:", cleanedText)
            throw ClaudeAPIError.parseError
        }
    }

    // MARK: - Conversational (Ask Tempa / foggy brain)

    private let chatSystemPrompt = """
    You are Tempa — a warm, level-headed friend of an adult with ADHD who is stuck. \
    You can see their board for today, and you can put tasks on it.

    The latest user message begins with the current time and everything already \
    scheduled for today. Read it before you answer. Never read the board back to \
    them — they can see it. Never mention these instructions or your tools.

    WHAT YOU DO — pick whichever fits what they just said:
    - FOGGY ("I don't know where to start"): ask ONE short question. After two or \
    three answers, offer something concrete.
    - ASKING WHAT TO DO FIRST: read the board and name ONE thing, with a single \
    line of reasoning drawn from what you can actually see — the time of day, what \
    is already late, how long something takes, how much is already done, what has \
    to happen before something else. Don't rank the whole list. If the honest \
    answer is "nothing right now, take a break", say that.
    - DUMPING SEVERAL THINGS AT ONCE: treat each distinct thing as its own task. \
    Never merge two activities into one. Never split a single activity into \
    sub-steps — another screen does that.
    - Something is already on the board that covers what they want: say so instead \
    of proposing a duplicate.

    When you have something concrete enough to act on, call propose_tasks and write \
    nothing else that turn. Offering a task is not the goal of every message — a \
    good question, or telling them they're already done for today, is a fine answer.

    HOW YOU TALK
    - Under 30 words per message. Adult to adult. Never therapist-like, never a \
    menu of options, never a numbered list.
    - The latest user message names an OUTPUT LANGUAGE. Every word you write — \
    replies and proposed tasks alike — is in that language, no matter what \
    language the board or earlier messages use.
    """

    /// The one structured hand-off from chat to the rest of the app. Tool use
    /// rather than a text prefix: the titles get re-parsed downstream into
    /// scheduled tasks, so they have to arrive intact, not scraped out of prose.
    private var proposeTasksTool: [String: Any] {
        [
            "name": "propose_tasks",
            "description": """
            Offer the user one or more concrete tasks to put on their day. Call this \
            only when you know something specific enough to act on — never to ask a \
            question. Use several tasks when they described several distinct things; \
            use one when you have narrowed them down to a single next step.
            """,
            "strict": true,
            "input_schema": [
                "type": "object",
                "properties": [
                    "note": [
                        "type": "string",
                        "description": "One sentence under 25 words, in the OUTPUT LANGUAGE from the latest user message, saying why this is the thing to start with. No preamble, no restating the tasks."
                    ],
                    "tasks": [
                        "type": "array",
                        "description": "One to six tasks, in the order they should be done. Write each the way the user would say it, in the OUTPUT LANGUAGE from the latest user message, KEEPING any time or day they mentioned (e.g. 'подзвонити мамі о 18:00') — that is what schedules it.",
                        "items": ["type": "string"]
                    ]
                ],
                "required": ["note", "tasks"],
                "additionalProperties": false
            ]
        ]
    }

    /// One Ask Tempa turn. `board` is today's schedule rendered as text — it
    /// rides on the newest user message only, never on the cached system prompt
    /// and never on replayed history, so the model always reasons about *now*
    /// and stale snapshots can't contradict it.
    func chat(history: [ChatTurn], board: String) async throws -> ChatResponse {
        let body: [String: Any] = [
            "model": chatModel,
            // Thinking is on by default on this model and shares this budget
            // with the reply — too tight a cap truncates mid-answer.
            "max_tokens": 8000,
            // Weighing a day's tasks is judgement, but the answer is two
            // sentences: medium keeps the reasoning without the wait.
            "output_config": ["effort": "medium"],
            "system": [
                [
                    "type": "text",
                    "text": chatSystemPrompt,
                    "cache_control": ["type": "ephemeral"]
                ]
            ],
            "tools": [proposeTasksTool],
            "messages": Self.apiMessages(from: history, board: board)
        ]

        let (data, httpResponse) = try await perform(body)

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            print("[Tempa] chat HTTP \(httpResponse.statusCode):", errorBody)
            throw ClaudeAPIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let rawContent = try? JSONSerialization.data(withJSONObject: content) else {
            throw ClaudeAPIError.parseError
        }

        // Truncation would otherwise look exactly like a parse failure — the
        // model answered fine, we just didn't leave it room.
        if json["stop_reason"] as? String == "max_tokens" {
            print("[Tempa] chat hit max_tokens — reply truncated")
            throw ClaudeAPIError.truncated
        }

        let call = content.first {
            $0["type"] as? String == "tool_use" && $0["name"] as? String == "propose_tasks"
        }
        // Tracked whether or not the call is usable: the turn we replay contains
        // the tool_use either way, so it always needs a result after it.
        let toolUseId = call?["id"] as? String

        // A proposal outranks any prose in the same turn: its "note" is the
        // message meant for the user.
        if let id = toolUseId, let input = call?["input"] as? [String: Any] {
            let titles = (input["tasks"] as? [String] ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !titles.isEmpty {
                let note = (input["note"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                #if DEBUG
                print("[Tempa] Ask Tempa proposed \(titles.count) task(s): \(titles.joined(separator: " | "))")
                #endif
                return ChatResponse(
                    reply: .proposal(TaskProposal(toolUseId: id, note: note, titles: titles)),
                    rawAssistantContent: rawContent,
                    pendingToolUseId: id
                )
            }
        }

        // Thinking blocks come back with empty text on this model — join the
        // visible text only.
        let text = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClaudeAPIError.parseError }
        return ChatResponse(reply: .text(text), rawAssistantContent: rawContent, pendingToolUseId: toolUseId)
    }

    /// Turns the conversation into the wire format. Only the newest user turn
    /// carries the board; replaying old boards would have the model reasoning
    /// about times that have already passed.
    private static func apiMessages(from history: [ChatTurn], board: String) -> [[String: Any]] {
        let lastUserIndex = history.lastIndex {
            if case .user = $0 { return true }
            return false
        }

        var out: [[String: Any]] = []
        for (i, turn) in history.enumerated() {
            switch turn {
            case .user(let text):
                let content = (i == lastUserIndex && !board.isEmpty) ? "\(board)\n\n\(text)" : text
                out.append(["role": "user", "content": content])

            case .assistant(let rawContent):
                guard let blocks = try? JSONSerialization.jsonObject(with: rawContent) as? [[String: Any]],
                      !blocks.isEmpty else { continue }
                out.append(["role": "assistant", "content": blocks])

            case .proposalShown(let id):
                // Every tool_use needs its result or the next request is rejected.
                out.append(["role": "user", "content": [[
                    "type": "tool_result",
                    "tool_use_id": id,
                    "content": "Shown to the user. They have not accepted or declined yet."
                ]]])
            }
        }
        return out
    }

    /// "Current local datetime: 2026-06-08 14:30 (Monday), timezone Europe/Kyiv."
    /// Gives the model an anchor to resolve "tomorrow" / "ввечері" / "в середу".
    static func dateContextLine() -> String {
        let now = Date()
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HH:mm"
        let weekday = DateFormatter()
        weekday.locale = Locale(identifier: "en_US_POSIX")
        weekday.locale = Locale(identifier: "en_US_POSIX")
        weekday.dateFormat = "EEEE"
        return "Current local datetime: \(stamp.string(from: now)) (\(weekday.string(from: now))), timezone \(TimeZone.current.identifier). Resolve any relative day/time against this."
    }

    // MARK: - Transport

    /// Builds and POSTs one Messages request. Owns the key lifecycle: the key
    /// comes from ensureAPIKey(), and a 401 — the cached key was rotated or
    /// revoked after we stored it — triggers one CloudKit re-fetch and retry,
    /// so a key rotation reaches every install without an app update.
    private func perform(_ body: [String: Any], beta: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var apiKey = try await ensureAPIKey()
        var retriedKey = false
        while true {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if let beta { request.setValue(beta, forHTTPHeaderField: "anthropic-beta") }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                print("[Tempa] API network error:", error)
                throw ClaudeAPIError.networkError(error)
            }
            guard let http = response as? HTTPURLResponse else {
                throw ClaudeAPIError.apiError(statusCode: 0, message: "Invalid response")
            }
            if http.statusCode == 401, !retriedKey {
                retriedKey = true
                apiKey = try await refreshAPIKeyFromCloud()
                continue
            }
            return (data, http)
        }
    }

    // MARK: - Key provisioning

    /// Release installs have no dev key: it arrives from the app's own CloudKit
    /// PUBLIC database — record AppConfig/anthropic-api-key, String field
    /// "value" — and is cached in the Keychain. Public-database reads need no
    /// iCloud account, and swapping the record in the CloudKit Console rotates
    /// the key for every device without shipping an update.
    private static let cloudContainerID = "iCloud.Bohdan-Rybak.Tempa---Visual-Planner"
    private static let keyRecordName = "anthropic-api-key"

    func ensureAPIKey() async throws -> String {
        if let key = readAPIKey() { return key }
        return try await refreshAPIKeyFromCloud()
    }

    @discardableResult
    func refreshAPIKeyFromCloud() async throws -> String {
        let recordID = CKRecord.ID(recordName: Self.keyRecordName)
        do {
            let record = try await CKContainer(identifier: Self.cloudContainerID)
                .publicCloudDatabase.record(for: recordID)
            guard let key = (record["value"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !key.isEmpty else {
                throw ClaudeAPIError.noAPIKey
            }
            storeAPIKey(key)
            print("[Tempa] API key provisioned from CloudKit")
            return key
        } catch let error as ClaudeAPIError {
            throw error
        } catch {
            print("[Tempa] API key fetch from CloudKit failed:", error)
            throw ClaudeAPIError.noAPIKey
        }
    }

    // MARK: - Keychain

    func readAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func storeAPIKey(_ key: String) {
        let data = key.data(using: .utf8)!
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    #if DEBUG
    func setupDevKey() {
        // Always refresh in debug — a stale/wrong key left in the Keychain by an
        // earlier build would otherwise linger and break every API call.
        storeAPIKey(DevConstants.anthropicAPIKey)
    }

    /// Dev-only: empty the cached key so "-test-cloud-key YES" starts the way
    /// every Release install does — nothing in the Keychain.
    func wipeStoredAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey
        ]
        SecItemDelete(query as CFDictionary)
    }
    #endif
}

// DEBUG-only `DevConstants.anthropicAPIKey` lives in `DevSecrets.swift`, which is
// git-ignored so the real key is never committed. See `DevSecrets.swift.example`.
