import Foundation
import Security

struct TaskBreakdown: Codable, Sendable {
    struct Step: Codable, Sendable {
        let title: String
        let duration: Int
        let icon: String
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

/// Counts AI requests made in the current calendar month (resets automatically).
/// Real usage shown in Settings — no fake numbers.
enum AIUsage {
    private static let monthKey = "aiUsageMonth"
    private static let countKey = "aiUsageCount"

    private static var currentMonth: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }

    static func record() {
        let d = UserDefaults.standard
        if d.string(forKey: monthKey) != currentMonth {
            d.set(currentMonth, forKey: monthKey)
            d.set(0, forKey: countKey)
        }
        d.set(d.integer(forKey: countKey) + 1, forKey: countKey)
    }

    /// Number of AI requests this month.
    static var thisMonth: Int {
        let d = UserDefaults.standard
        return d.string(forKey: monthKey) == currentMonth ? d.integer(forKey: countKey) : 0
    }
}

enum ClaudeAPIError: Error, LocalizedError {
    case networkError(Error)
    case apiError(statusCode: Int, message: String)
    case parseError
    case noAPIKey
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .apiError(let code, let msg): return "API error \(code): \(msg)"
        case .parseError: return "Failed to parse AI response"
        case .noAPIKey: return "API key not configured"
        case .rateLimited: return "Daily limit reached"
        }
    }
}

final class ClaudeAPIClient: Sendable {
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-4-6"
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
    - Tone: encouraging but not patronizing. Adult-to-adult.
    - Write each step "title" and "cleanTitle" in the SAME language the user wrote \
    the task in (Ukrainian task → Ukrainian, German → German, etc.). Keep the JSON \
    keys, the "icon" values and all schedule values exactly as specified — always English.
    - Output STRICT JSON only, no preamble, no markdown fences.

    SCHEDULE — figure out WHEN the user wants this, and always turn it into a concrete time.
    The user message begins with the current local datetime; resolve everything against it.
    Fill the "schedule" object:
    - "cleanTitle": the task with the time/date words removed (e.g. "приготувати вечерю \
    після роботи" → "приготувати вечерю"). If there were none, repeat the task as-is.
    - "hasTime": true if the user mentioned ANY time or day — including vague or colloquial \
    ones ("після роботи", "перед сном", "ввечері", "коли прокинусь"). false only if nothing.
    - "date": the intended day as "yyyy-MM-dd". If a time is given with no day, use today.
    - "time": 24-hour "HH:mm" — your best concrete time for what they meant. ALWAYS set this \
    when hasTime is true. NEVER leave it null when there is any time hint.
    - "precise": true ONLY when the user stated an exact clock time ("о 15:00", "at 3pm", \
    "пів на десяту", "за 30 хвилин"); false for approximate or contextual phrases.
    Map contextual phrases to concrete times (defaults — use judgement):
    "перед роботою" 07:30 · "вранці"/"зранку"/"рано" 08:00 · "опівдні"/"в обід" 12:00 · \
    "після обіду"/"вдень" 14:00 · "після роботи"/"after work" 18:00 · "ввечері"/"evening" \
    19:00 · "перед сном"/"на ніч" 22:00 · "вночі"/"пізно" 22:00.
    Days: "завтра" → tomorrow · "післязавтра" → +2 days · weekday names ("в середу") → \
    that weekday's next date · "через N годин/хвилин" → from now, precise=true.
    If an exact time with no day already passed today, use tomorrow.
    If the user mentioned NO time at all: hasTime=false, precise=false, date and time null.

    JSON shape:
    {
      "cleanTitle": "task without time words",
      "schedule": { "hasTime": true, "precise": false, "date": "2026-06-09", "time": "18:00" },
      "steps": [
        { "title": "...", "duration": 10, "icon": "trash" }
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
    - "title": short, in the user's language, with the time words removed.
    - "category": exactly one of: work, personal, health, routine, social, rest.
    - "durationMinutes": a sensible estimate, 15–120.
    - "icon": one SF Symbol that fits the task, chosen ONLY from this list: \(ClaudeAPIClient.iconVocabulary).
    - "hasTime": true if a time or day was said for THIS task (including vague ones like \
    "після обіду", "ввечері"). false if no time hint for it.
    - "date": "yyyy-MM-dd" (today if a time but no day was given), else null.
    - "time": 24-hour "HH:mm" — your concrete time. Contextual defaults: вранці/зранку 08:00, \
    опівдні/в обід 12:00, після обіду/вдень 14:00, після роботи 18:00, ввечері 19:00, перед сном 22:00.
    - "precise": true only when an exact clock time was said ("о 15:00", "о пів на десяту", "о 9 ранку").
    If a task has no time hint, set hasTime=false and date/time null — the app places it in order.

    RECURRENCE — for things that repeat (very common for meds/habits):
    - SEVERAL TIMES A DAY ("3 рази на день", "тричі на добу", "зранку, в обід і ввечері", \
    "twice a day"): set "times" to the list of 24h "HH:mm" — e.g. ["08:00","13:00","19:00"]. \
    Use the same contextual mapping (зранку 08:00, обід 13:00, ввечері 19:00, перед сном 22:00). \
    Set hasTime=true and "time" to the first of them. If they only say a count ("3 рази") with \
    no parts of day, spread them across waking hours (e.g. 3× → 08:00, 14:00, 20:00).
    - OVER SEVERAL DAYS ("10 днів підряд", "протягом тижня", "10 days in a row", "курс 7 днів"): \
    set "repeatDays" to that number of consecutive days (e.g. 10). "цей тиждень"/"this week" = 7. \
    "date" = the first day (today unless another start is given). Default repeatDays=1 (no repeat).
    - Output ONE task object with "times" and/or "repeatDays" — do NOT emit a separate object \
    per occurrence. Keep "title" clean of the count/frequency words ("Випити антибіотик").

    Keep the user's spoken order. Output STRICT JSON only, no markdown fences:
    { "tasks": [ { "title": "Випити вітамін D", "category": "health", "durationMinutes": 5, "icon": "pills", "hasTime": true, "precise": false, "date": "2026-06-09", "time": "08:00", "times": ["08:00","14:00","20:00"], "repeatDays": 10 } ] }
    """

    /// Split a spoken brain-dump into several scheduled tasks ("plan my day").
    func planTasks(from brainDump: String) async throws -> DayPlan {
        guard let apiKey = readAPIKey() else { throw ClaudeAPIError.noAPIKey }

        let userContent = "\(Self.dateContextLine())\n\nBrain dump: \(brainDump)"
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1500,
            "system": [
                ["type": "text", "text": planSystemPrompt, "cache_control": ["type": "ephemeral"]]
            ],
            "messages": [["role": "user", "content": userContent]]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeAPIError.apiError(statusCode: 0, message: "Invalid response")
        }
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
            AIUsage.record()
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
        guard let apiKey = readAPIKey() else {
            throw ClaudeAPIError.noAPIKey
        }

        let userContent = "\(Self.dateContextLine())\n\nTask: \(task)"

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

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            print("[Tempa] breakDown network error:", error)
            throw ClaudeAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.apiError(statusCode: 0, message: "Invalid response")
        }

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
            AIUsage.record()
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
    You are Tempa, a warm and calm assistant for adults with ADHD. \
    The user feels overwhelmed and can't figure out what to do. \
    Your job: ask 2-3 short, simple questions to narrow down ONE concrete task. \
    RULES:
    - Keep messages under 30 words. Be casual, adult-to-adult.
    - Never list options — ask one question at a time.
    - After 2-3 exchanges, suggest ONE specific task.
    - When you suggest a task, start your message with "TASK:" followed by the task title, \
      then on a new line explain briefly why.
    - Don't be therapist-like. Be a friend who helps you start.
    - Reply in the SAME language the user writes in. Always keep the literal \
    "TASK:" prefix in English, even when the rest of the message is in another language.
    """

    func chat(messages: [(role: String, content: String)]) async throws -> String {
        guard let apiKey = readAPIKey() else {
            throw ClaudeAPIError.noAPIKey
        }

        let apiMessages = messages.map { ["role": $0.role, "content": $0.content] }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 256,
            "system": [
                [
                    "type": "text",
                    "text": chatSystemPrompt,
                    "cache_control": ["type": "ephemeral"]
                ]
            ],
            "messages": apiMessages
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClaudeAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            throw ClaudeAPIError.apiError(statusCode: code, message: errorBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let textBlock = content.first(where: { $0["type"] as? String == "text" }),
              let text = textBlock["text"] as? String else {
            throw ClaudeAPIError.parseError
        }

        return text
    }

    /// "Current local datetime: 2026-06-08 14:30 (Monday), timezone Europe/Kyiv."
    /// Gives the model an anchor to resolve "tomorrow" / "ввечері" / "в середу".
    static func dateContextLine() -> String {
        let now = Date()
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HH:mm"
        let weekday = DateFormatter()
        weekday.locale = Locale(identifier: "en_US_POSIX")
        weekday.dateFormat = "EEEE"
        return "Current local datetime: \(stamp.string(from: now)) (\(weekday.string(from: now))), timezone \(TimeZone.current.identifier). Resolve any relative day/time against this."
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
    #endif
}

// DEBUG-only `DevConstants.anthropicAPIKey` lives in `DevSecrets.swift`, which is
// git-ignored so the real key is never committed. See `DevSecrets.swift.example`.
