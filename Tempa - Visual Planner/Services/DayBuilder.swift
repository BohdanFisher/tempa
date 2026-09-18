import Foundation
import CoreData

/// What the funnel collected about the user's first day: what they said they
/// have on, and whether they were planning today or tomorrow. Parked in
/// UserDefaults from the moment the paywall opens until a purchase turns it
/// into real tasks — on either paywall (the funnel's cover, or the root one
/// after a kill-and-relaunch).
struct FirstDayPlan: Codable {
    var dump: String
    var tasks: [PlannedTask]
    var stashedAt: Date
}

/// Turns onboarding answers into a day the user can see on Home the second
/// they've paid — the way Structured seeds a day, but from THEIR answers:
/// the things they typed, laid out from now (or from tomorrow's wake time),
/// around the routine every day has anyway (breakfast, lunch, a light block
/// at their energy dip, dinner, five minutes to plan tomorrow, winding down).
///
/// Everything here is a plain TaskBlock the user can move, edit or delete;
/// routines carry `notes == "tempa:auto"` so reminders leave them alone.
enum DayBuilder {
    struct Draft: Identifiable {
        let id = UUID()
        var title: String
        var category: String
        var icon: String
        var start: Date
        var minutes: Int
        /// Shared by every instance of one routine / repeating task.
        var group: UUID?
        /// "tempa:auto" for the seeded routine, "tempa:auto:plan" for the
        /// evening "plan tomorrow" block (that one may remind), nil for the
        /// user's own tasks.
        var notes: String?
    }

    static let autoNote = "tempa:auto"
    static let autoPlanNote = "tempa:auto:plan"
    /// How many days of routine to seed. A week is enough to feel like a
    /// rhythm and short enough not to become a pile.
    static let routineDays = 7
    /// A day is 16 waking hours, the same window the Me tab's battery uses.
    static let wakingSeconds: TimeInterval = 16 * 3600

    // MARK: - Which day

    /// Today's (or the given day's) wake instant from the stored wake time.
    static func wakeInstant(on day: Date, wake: Date) -> Date {
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: wake)
        return cal.date(bySettingHour: hm.hour ?? 7, minute: hm.minute ?? 30, second: 0,
                        of: cal.startOfDay(for: day)) ?? cal.startOfDay(for: day)
    }

    /// Someone typing their plan late in their day is planning tomorrow:
    /// under three waking hours left means "today" would be a list of
    /// things they can't start.
    static func plansTomorrow(now: Date, wake: Date) -> Bool {
        now > wakeInstant(on: now, wake: wake).addingTimeInterval(wakingSeconds - 3 * 3600)
    }

    static func targetDay(now: Date, wake: Date) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        return plansTomorrow(now: now, wake: wake)
            ? (cal.date(byAdding: .day, value: 1, to: today) ?? today)
            : today
    }

    // MARK: - Routine

    /// The blocks every day has, anchored to the user's own wake time and
    /// energy dip, for `days` days starting at `firstDay`. Blocks already in
    /// the past (a plan typed at 15:00 needs no breakfast) are left out.
    static func routine(firstDay: Date, days: Int, wake: Date, dip: Date?, now: Date) -> [Draft] {
        let cal = Calendar.current
        let groups = (0..<6).map { _ in UUID() }
        var drafts: [Draft] = []
        for offset in 0..<days {
            guard let day = cal.date(byAdding: .day, value: offset, to: firstDay) else { continue }
            let w = wakeInstant(on: day, wake: wake)
            var blocks: [(Int, String, String, String, TimeInterval, Int, String)] = [
                // (group, title key, category, icon, offset from wake, minutes, notes)
                (0, "Breakfast", "routine", "cup.and.saucer", 15 * 60, 20, autoNote),
                (1, "Lunch", "routine", "fork.knife", 5 * 3600, 40, autoNote),
                (3, "Dinner", "routine", "fork.knife", 11.5 * 3600, 45, autoNote),
                (4, "Tomorrow's plan — 5 minutes", "personal", "mic.fill", 14 * 3600, 5, autoPlanNote),
                (5, "Wind down", "rest", "bed.double", 15 * 3600, 30, autoNote),
            ]
            if let dip {
                let hm = cal.dateComponents([.hour, .minute], from: dip)
                let dipInstant = cal.date(bySettingHour: hm.hour ?? 15, minute: hm.minute ?? 0,
                                          second: 0, of: cal.startOfDay(for: day)) ?? w
                blocks.append((2, "Recharge break", "rest", "leaf", dipInstant.timeIntervalSince(w), 15, autoNote))
            }
            for (g, key, cat, icon, delta, minutes, note) in blocks {
                let start = w.addingTimeInterval(delta)
                guard start > now else { continue }
                drafts.append(Draft(
                    title: routineTitle(key),
                    category: cat, icon: icon, start: start, minutes: minutes,
                    group: groups[g], notes: note
                ))
            }
        }
        return drafts.sorted { $0.start < $1.start }
    }

    /// Literal keys on purpose: a key built at runtime is invisible to
    /// Xcode's string extraction, which then marks the translations stale —
    /// one "remove stale strings" away from an English-only routine.
    private static func routineTitle(_ key: String) -> String {
        switch key {
        case "Breakfast": return String(localized: "Breakfast", bundle: .appLanguage)
        case "Lunch": return String(localized: "Lunch", bundle: .appLanguage)
        case "Dinner": return String(localized: "Dinner", bundle: .appLanguage)
        case "Recharge break": return String(localized: "Recharge break", bundle: .appLanguage)
        case "Wind down": return String(localized: "Wind down", bundle: .appLanguage)
        default: return String(localized: "Tomorrow's plan — 5 minutes", bundle: .appLanguage)
        }
    }

    // MARK: - The user's own tasks

    /// Lays the typed tasks out on `targetDay`: anything with a time keeps
    /// it (a time already gone today is treated as "no time"), everything
    /// else flows from now — or from an hour after tomorrow's wake — into
    /// the gaps between the routine blocks, ten minutes apart, never on top
    /// of each other. Repeats ("3 times a day", "for a week") expand like
    /// the day planner does, capped at a week.
    static func place(_ planned: [PlannedTask], on targetDay: Date, wake: Date, dip: Date?,
                      now: Date, around fixed: [Draft]) -> [Draft] {
        let cal = Calendar.current
        let isToday = cal.isDate(targetDay, inSameDayAs: now)
        let wakeT = wakeInstant(on: targetDay, wake: wake)
        let dayEnd = wakeT.addingTimeInterval(wakingSeconds - 30 * 60)
        var occupied: [(Date, Date)] = fixed.map { ($0.start, $0.start.addingTimeInterval(TimeInterval($0.minutes) * 60)) }
        var cursor = isToday
            ? max(roundUp(now.addingTimeInterval(10 * 60)), wakeT.addingTimeInterval(15 * 60))
            : wakeT.addingTimeInterval(60 * 60)
        var drafts: [Draft] = []

        func free(_ s: Date, _ minutes: Int) -> Bool {
            let e = s.addingTimeInterval(TimeInterval(minutes) * 60)
            return !occupied.contains { $0.0 < e && $0.1 > s }
        }
        func firstFree(from: Date, minutes: Int) -> Date {
            var s = from
            while s < dayEnd {
                if free(s, minutes) { return s }
                s = s.addingTimeInterval(5 * 60)
            }
            return from   // the day is full — stack at the cursor rather than lose it
        }

        for task in planned {
            let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let minutes = min(max(task.durationMinutes ?? 30, 5), 240)
            let category = Cat.all.contains { $0.0 == (task.category ?? "") } ? task.category! : "personal"
            let icon = (task.icon?.isEmpty == false && task.icon != "null") ? task.icon! : Cat.icon(for: category)
            let repeatDays = min(max(task.repeatDays ?? 1, 1), 7)
            let group = repeatDays > 1 || (task.times?.count ?? 0) > 1 ? UUID() : nil

            // Which clock times on the target day?
            var clocks: [(Int, Int)] = (task.times ?? []).compactMap(parseHM)
            if clocks.isEmpty, task.hasTime == true, let t = parseHM(task.time ?? "") { clocks = [t] }
            var starts: [Date] = []
            for (h, m) in clocks {
                guard let at = cal.date(bySettingHour: h, minute: m, second: 0, of: targetDay) else { continue }
                if isToday && at < now { continue }   // that moment is gone — flow it instead
                starts.append(at)
            }
            if starts.isEmpty {
                let s = firstFree(from: cursor, minutes: minutes)
                starts = [s]
                cursor = s.addingTimeInterval(TimeInterval(minutes + 10) * 60)
            }
            for s in starts {
                occupied.append((s, s.addingTimeInterval(TimeInterval(minutes) * 60)))
                for d in 0..<repeatDays {
                    guard let day = cal.date(byAdding: .day, value: d, to: s) else { continue }
                    drafts.append(Draft(title: title, category: category, icon: icon,
                                        start: day, minutes: minutes, group: group, notes: nil))
                }
            }
        }
        return drafts.sorted { $0.start < $1.start }
    }

    /// The full first day (or week): routine plus the user's tasks.
    static func build(plan: FirstDayPlan?, wake: Date, dip: Date?, now: Date) -> [Draft] {
        let day = targetDay(now: now, wake: wake)
        let routineDrafts = routine(firstDay: day, days: routineDays, wake: wake, dip: dip, now: now)
        let own = place(plan?.tasks ?? [], on: day, wake: wake, dip: dip, now: now,
                        around: routineDrafts.filter { Calendar.current.isDate($0.start, inSameDayAs: day) })
        return (routineDrafts + own).sorted { $0.start < $1.start }
    }

    /// What the funnel screen shows: the user's tasks with their times on
    /// the target day, exactly as they will land on Home.
    static func preview(_ planned: [PlannedTask], wake: Date, dip: Date?, now: Date) -> [Draft] {
        let day = targetDay(now: now, wake: wake)
        let routineDrafts = routine(firstDay: day, days: 1, wake: wake, dip: dip, now: now)
        return place(planned, on: day, wake: wake, dip: dip, now: now, around: routineDrafts)
            .filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
    }

    // MARK: - Writing

    static func write(_ drafts: [Draft], into context: NSManagedObjectContext) {
        for d in drafts {
            let task = TaskBlock(context: context)
            task.id = UUID()
            task.title = d.title
            task.iconName = d.icon
            task.category = d.category
            task.startTime = d.start
            task.durationMinutes = Int32(d.minutes)
            task.createdAt = Date()
            task.parentTaskId = d.group
            task.notes = d.notes
        }
        try? context.save()
    }

    // MARK: - Helpers

    static func roundUp(_ date: Date, toMinutes step: Int = 5) -> Date {
        let interval = TimeInterval(step * 60)
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / interval).rounded(.up) * interval)
    }

    nonisolated static func parseHM(_ s: String) -> (Int, Int)? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }
}

/// When the AI can't be reached in the funnel, the typed day still becomes a
/// day: split on the separators people use when listing things (new lines,
/// commas, semicolons, bullets, "and" in the app's languages), one task each.
enum FallbackDayPlan {
    private static let ands = [" and ", " та ", " і ", " und ", " y ", " et ", " e ", " og ", " ja ", " en "]

    static func generate(from text: String) -> [PlannedTask] {
        var pieces = [text]
        for sep in ["\n", ",", ";", "•", " / "] + ands {
            pieces = pieces.flatMap { $0.components(separatedBy: sep) }
        }
        return pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "-–•.")) }
            .filter { $0.count >= 2 }
            .prefix(8)
            .map { PlannedTask(title: $0, category: "personal", durationMinutes: 30, icon: "circle",
                               hasTime: false, precise: nil, date: nil, time: nil, times: nil, repeatDays: nil) }
    }
}
