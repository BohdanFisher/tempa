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

/// Turns what the user typed in the funnel into a day they can see on Home
/// the second they've paid: THEIR things, laid out from now (or from
/// tomorrow's wake time) around whatever their calendar already holds.
///
/// Nothing is invented for them — no breakfast, no lunch, no "wind down".
/// People eat when they eat; a planner that schedules their meals is a
/// planner they have to clean up before they can use it.
///
/// Everything here is a plain TaskBlock the user can move, edit or delete.
enum DayBuilder {
    struct Draft: Identifiable {
        let id = UUID()
        var title: String
        var category: String
        var icon: String
        var start: Date
        var minutes: Int
        /// Shared by every instance of one repeating task.
        var group: UUID?
        /// The calendar marker for a block mirrored from the phone's
        /// calendar (preview only — the mirror itself writes those), nil
        /// for the user's own tasks.
        var notes: String?

        var isFromCalendar: Bool { notes?.hasPrefix(CalendarSync.notePrefix) == true }
    }

    /// Tag of the routine blocks (meals, breaks…) that earlier versions
    /// seeded on their own. Nothing writes it any more; it is kept so the
    /// leftovers can be found and cleared.
    static let autoNote = "tempa:auto"
    /// A day is 16 waking hours.
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

    // MARK: - The user's own tasks

    /// Lays the typed tasks out on `targetDay`: anything with a time keeps
    /// it (a time already gone today is treated as "no time"), everything
    /// else goes where SlotFinder says — the part of the day that suits it,
    /// in a gap between what's already `busy`, never on top of each other.
    /// Repeats ("3 times a day", "for a week") expand like the day planner
    /// does, capped at a week.
    static func place(_ planned: [PlannedTask], on targetDay: Date, wake: Date, dip: Date?,
                      now: Date, around busy: [DateInterval]) -> [Draft] {
        let cal = Calendar.current
        let isToday = cal.isDate(targetDay, inSameDayAs: now)
        let rhythm = SlotFinder.Rhythm(wake: wake, dip: dip)
        var occupied = busy
        var drafts: [Draft] = []

        struct Item {
            let title: String, minutes: Int, category: String, icon: String
            let repeatDays: Int, group: UUID?
            let task: PlannedTask
            /// Clock times the user SAID, still ahead on the target day.
            let said: [(Date, Bool)]   // (instant, exact?)
        }
        let items: [Item] = planned.compactMap { task -> Item? in
            let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let minutes = min(max(task.durationMinutes ?? 30, 5), 240)
            let category = Cat.all.contains { $0.0 == (task.category ?? "") } ? task.category! : "personal"
            let icon = (task.icon?.isEmpty == false && task.icon != "null") ? task.icon! : Cat.icon(for: category)
            let repeatDays = min(max(task.repeatDays ?? 1, 1), 7)
            let group = repeatDays > 1 || (task.times?.count ?? 0) > 1 ? UUID() : nil

            var clocks: [(Int, Int)] = (task.times ?? []).compactMap(parseHM)
            if clocks.isEmpty, task.hasTime == true, let t = parseHM(task.time ?? "") { clocks = [t] }
            let exact = task.precise == true || clocks.count > 1
            let said: [(Date, Bool)] = clocks.compactMap { h, m -> (Date, Bool)? in
                guard let at = cal.date(bySettingHour: h, minute: m, second: 0, of: targetDay) else { return nil }
                return isToday && at < now ? nil : (at, exact)   // that moment is gone — find it a place instead
            }
            return Item(title: title, minutes: minutes, category: category, icon: icon,
                        repeatDays: repeatDays, group: group, task: task, said: said)
        }

        // Exact times are appointments: they take their place FIRST, so that
        // nothing placed by us — even a task said earlier — lands on them.
        for item in items {
            for (at, exact) in item.said where exact {
                occupied.append(DateInterval(start: at, duration: TimeInterval(item.minutes) * 60))
            }
        }

        for item in items {
            let taken = SlotFinder.projecting(occupied, onto: targetDay, repeatDays: item.repeatDays)
            var starts: [Date] = []
            for (at, exact) in item.said {
                if exact {
                    starts.append(at)
                } else {
                    // "After work" is an anchor, not an appointment: slide to
                    // the nearest gap.
                    let s = SlotFinder.nearestFree(to: at, minutes: item.minutes, now: now, busy: taken)
                    occupied.append(DateInterval(start: s, duration: TimeInterval(item.minutes) * 60))
                    starts.append(s)
                }
            }
            if starts.isEmpty {
                let s = SlotFinder.place(item.task.slotRequest(minutes: item.minutes), on: targetDay, now: now,
                                         rhythm: rhythm, busy: taken)
                occupied.append(DateInterval(start: s, duration: TimeInterval(item.minutes) * 60))
                starts = [s]
            }
            for s in starts {
                for d in 0..<item.repeatDays {
                    guard let day = cal.date(byAdding: .day, value: d, to: s) else { continue }
                    drafts.append(Draft(title: item.title, category: item.category, icon: item.icon,
                                        start: day, minutes: item.minutes, group: item.group, notes: nil))
                }
            }
        }
        return drafts.sorted { $0.start < $1.start }
    }

    /// The first day: the user's tasks, around what is already taken.
    static func build(plan: FirstDayPlan?, wake: Date, dip: Date?, now: Date,
                      around busy: [DateInterval]) -> [Draft] {
        place(plan?.tasks ?? [], on: targetDay(now: now, wake: wake), wake: wake, dip: dip,
              now: now, around: busy)
    }

    /// What the funnel screen shows: the target day exactly as it will land
    /// on Home — the calendar's blocks (when connected) and the user's tasks
    /// laid out around them.
    /// `busy` is what the calendars hold for the coming week (a repeating
    /// task has to fit every one of its days); `calendar` is the target
    /// day's events, shown alongside.
    static func preview(_ planned: [PlannedTask], wake: Date, dip: Date?, now: Date,
                        calendar: [Draft], busy: [DateInterval]) -> [Draft] {
        let day = targetDay(now: now, wake: wake)
        let ahead = calendar.filter { $0.start.addingTimeInterval(TimeInterval($0.minutes) * 60) > now }
        let own = place(planned, on: day, wake: wake, dip: dip, now: now, around: busy)
            .filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
        return (ahead + own).sorted { $0.start < $1.start }
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

    /// One-time cleanup for installs that were seeded with a week of routine
    /// (breakfast, lunch, dinner, breaks) by an earlier version: whatever of
    /// it is still unticked goes. Ticked ones stay — that is the user's
    /// history, not our template.
    static func removeSeededRoutine(from context: NSManagedObjectContext) {
        let doneKey = "didRemoveSeededRoutine"
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        UserDefaults.standard.set(true, forKey: doneKey)
        let req = NSFetchRequest<TaskBlock>(entityName: "TaskBlock")
        req.predicate = NSPredicate(format: "isCompleted == NO AND notes BEGINSWITH %@", autoNote)
        let leftovers = (try? context.fetch(req)) ?? []
        guard !leftovers.isEmpty else { return }
        leftovers.forEach(context.delete)
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
