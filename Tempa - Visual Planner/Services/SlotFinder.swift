import Foundation
import CoreData

/// Where a task with no fixed time should go.
///
/// The AI reads the task and says how heavy it is and which part of the day
/// suits it (and may suggest a clock time). This type does the arithmetic a
/// language model is bad at: it knows exactly which minutes are taken — by
/// the user's tasks and by what came in from their calendar — and never puts
/// two things on top of each other.
///
/// The day is cut into three windows hung on the user's own wake time, not on
/// the wall clock: someone who wakes at 11:00 has their "morning" at noon.
enum SlotFinder {
    enum DayPart: String, CaseIterable {
        case morning, afternoon, evening
    }

    enum Effort: String {
        case low, medium, high
    }

    /// The user's rhythm, from onboarding / Settings.
    struct Rhythm {
        var wake: Date
        var dip: Date?
    }

    /// What is known about a task that needs a place.
    struct Request {
        var minutes: Int
        /// The model's own pick, "HH:mm" → (h, m). Used when it really is free.
        var suggested: (Int, Int)?
        var part: DayPart?
        var effort: Effort?
    }

    /// Candidate starts sit on the quarter hour — 10:15 reads as a plan,
    /// 10:10 reads as a computer.
    private static let step: TimeInterval = 15 * 60
    /// Breathing room between two blocks: nobody with ADHD teleports from
    /// one thing into the next.
    private static let gap: TimeInterval = 5 * 60

    // MARK: - Windows

    static func window(_ part: DayPart, on day: Date, rhythm: Rhythm) -> DateInterval {
        let w = DayBuilder.wakeInstant(on: day, wake: rhythm.wake)
        switch part {
        case .morning: return DateInterval(start: w.addingTimeInterval(45 * 60), end: w.addingTimeInterval(5 * 3600))
        case .afternoon: return DateInterval(start: w.addingTimeInterval(5 * 3600), end: w.addingTimeInterval(10 * 3600))
        case .evening: return DateInterval(start: w.addingTimeInterval(10 * 3600), end: w.addingTimeInterval(15 * 3600))
        }
    }

    static func dayEnd(on day: Date, rhythm: Rhythm) -> Date {
        DayBuilder.wakeInstant(on: day, wake: rhythm.wake)
            .addingTimeInterval(DayBuilder.wakingSeconds - 30 * 60)
    }

    private static func dipInterval(on day: Date, rhythm: Rhythm) -> DateInterval? {
        guard let dip = rhythm.dip else { return nil }
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: dip)
        guard let at = cal.date(bySettingHour: hm.hour ?? 15, minute: hm.minute ?? 0, second: 0,
                                of: cal.startOfDay(for: day)) else { return nil }
        return DateInterval(start: at, duration: 90 * 60)
    }

    // MARK: - Placing

    /// A start for a task nobody gave a time to. Order of preference:
    /// the model's suggested time when it's genuinely free → the part of the
    /// day that suits the task (heavy work in the morning peak and never in
    /// the energy dip; light things INTO the dip) → anywhere left today →
    /// right after `now` (a full day stacks rather than loses the task).
    static func place(_ request: Request, on day: Date, now: Date, rhythm: Rhythm,
                      busy: [DateInterval]) -> Date {
        let cal = Calendar.current
        let minutes = max(request.minutes, 5)
        let isToday = cal.isDate(day, inSameDayAs: now)
        let end = dayEnd(on: day, rhythm: rhythm)
        let earliest = isToday
            ? DayBuilder.roundUp(now.addingTimeInterval(10 * 60), toMinutes: 15)
            : window(.morning, on: day, rhythm: rhythm).start

        var taken = busy
        // Heavy work stays out of the dip — that hour is kept light on purpose.
        if request.effort == .high, let dip = dipInterval(on: day, rhythm: rhythm) {
            taken.append(dip)
        }

        if let (h, m) = request.suggested,
           let at = cal.date(bySettingHour: h, minute: m, second: 0, of: cal.startOfDay(for: day)),
           at >= earliest.addingTimeInterval(-10 * 60),
           isFree(at, minutes: minutes, busy: taken) {
            return at
        }

        var windows: [DateInterval] = []
        if request.effort == .low, request.part == nil, let dip = dipInterval(on: day, rhythm: rhythm) {
            windows.append(dip)
        }
        windows += order(for: request, suggestedOn: day, rhythm: rhythm)
            .map { window($0, on: day, rhythm: rhythm) }

        for w in windows {
            if let s = firstFree(in: w, earliest: earliest, minutes: minutes, latestEnd: end, busy: taken) {
                return s
            }
        }
        // No window has room: anything left before the day ends — the dip
        // included, a heavy task in the dip beats a task nowhere.
        let rest = DateInterval(start: min(earliest, end), end: end)
        if let s = firstFree(in: rest, earliest: earliest, minutes: minutes, latestEnd: end, busy: busy) {
            return s
        }
        // Past the end of the day, or a day with no gap at all.
        let lateNight = DateInterval(start: earliest, duration: 3 * 3600)
        if let s = firstFree(in: lateNight, earliest: earliest, minutes: minutes,
                             latestEnd: lateNight.end.addingTimeInterval(TimeInterval(minutes) * 60), busy: busy) {
            return s
        }
        // Truly nothing: queue up behind the last thing on that day. The
        // caller adds each placed task to `busy`, so several overflow tasks
        // line up one after another instead of landing on the same minute.
        let lastEnd = busy.filter { cal.isDate($0.start, inSameDayAs: day) && $0.end > earliest }.map(\.end).max()
        var queued = DayBuilder.roundUp((lastEnd ?? earliest).addingTimeInterval(gap), toMinutes: 15)
        // …and past whatever was queued there before (it may run over midnight).
        for _ in 0..<96 where !isFree(queued, minutes: minutes, busy: busy) {
            queued = queued.addingTimeInterval(step)
        }
        return queued
    }

    /// What's taken on the FOLLOWING days, shifted back onto `day` — so a task
    /// that repeats for a week gets a time that is free on every one of its
    /// days, not just the first.
    static func projecting(_ busy: [DateInterval], onto day: Date, repeatDays: Int) -> [DateInterval] {
        guard repeatDays > 1 else { return busy }
        let cal = Calendar.current
        let first = cal.startOfDay(for: day)
        var out = busy
        for offset in 1..<repeatDays {
            guard let other = cal.date(byAdding: .day, value: offset, to: first) else { continue }
            for interval in busy where cal.isDate(interval.start, inSameDayAs: other) {
                if let s = cal.date(byAdding: .day, value: -offset, to: interval.start) {
                    out.append(DateInterval(start: s, duration: interval.duration))
                }
            }
        }
        return out
    }

    /// "This evening", "after lunch": the model turned the words into an
    /// anchor time. Keep as close to it as the day allows — forward first
    /// (up to three hours), then a little backward, else the anchor itself.
    static func nearestFree(to anchor: Date, minutes: Int, now: Date, busy: [DateInterval]) -> Date {
        let minutes = max(minutes, 5)
        let floor = now.addingTimeInterval(60)
        if anchor >= floor, isFree(anchor, minutes: minutes, busy: busy) { return anchor }
        var s = DayBuilder.roundUp(max(anchor, floor), toMinutes: 15)
        let forwardLimit = anchor.addingTimeInterval(3 * 3600)
        while s <= forwardLimit {
            if isFree(s, minutes: minutes, busy: busy) { return s }
            s = s.addingTimeInterval(step)
        }
        s = DayBuilder.roundUp(anchor, toMinutes: 15).addingTimeInterval(-step)
        let backwardLimit = max(anchor.addingTimeInterval(-2 * 3600), floor)
        while s >= backwardLimit {
            if isFree(s, minutes: minutes, busy: busy) { return s }
            s = s.addingTimeInterval(-step)
        }
        return anchor
    }

    // MARK: - Pieces

    /// Which windows to try, best first.
    private static func order(for request: Request, suggestedOn day: Date, rhythm: Rhythm) -> [DayPart] {
        var preferred = request.part
        // A suggested time that turned out to be taken still says which part
        // of the day the model had in mind.
        if preferred == nil, let (h, m) = request.suggested,
           let at = Calendar.current.date(bySettingHour: h, minute: m, second: 0,
                                          of: Calendar.current.startOfDay(for: day)) {
            preferred = DayPart.allCases.first { window($0, on: day, rhythm: rhythm).contains(at) }
        }
        if let preferred {
            // The preferred window, then its neighbours — nearest first,
            // the later one on a tie (a slipped task slips forward).
            let all = DayPart.allCases
            let i = all.firstIndex(of: preferred)!
            return all.enumerated()
                .sorted { a, b in
                    let da = abs(a.offset - i), db = abs(b.offset - i)
                    return da != db ? da < db : a.offset > b.offset
                }
                .map(\.element)
        }
        switch request.effort {
        case .low: return [.afternoon, .evening, .morning]
        // Heavy → the morning peak. Medium/unknown → simply the first gap.
        default: return [.morning, .afternoon, .evening]
        }
    }

    private static func firstFree(in window: DateInterval, earliest: Date, minutes: Int,
                                  latestEnd: Date, busy: [DateInterval]) -> Date? {
        var s = DayBuilder.roundUp(max(window.start, earliest), toMinutes: 15)
        while s < window.end {
            guard s.addingTimeInterval(TimeInterval(minutes) * 60) <= latestEnd else { return nil }
            if isFree(s, minutes: minutes, busy: busy) { return s }
            s = s.addingTimeInterval(step)
        }
        return nil
    }

    static func isFree(_ start: Date, minutes: Int, busy: [DateInterval]) -> Bool {
        let s = start.addingTimeInterval(-gap)
        let e = start.addingTimeInterval(TimeInterval(minutes) * 60 + gap)
        return !busy.contains { $0.start < e && $0.end > s }
    }

    // MARK: - What's taken

    /// Every block still ahead of the user between two instants: their own
    /// tasks and the ones mirrored from the calendar. Finished tasks don't
    /// hold their slot.
    ///
    /// `includeCalendar: false` is for anything that LEAVES the phone (the
    /// AI prompt): nothing that came from a calendar — Apple's or Google's,
    /// not even "this hour is taken" — is ever part of it. Placement on the
    /// phone uses the full picture, so the result is the same.
    static func busy(from: Date, to: Date, context: NSManagedObjectContext,
                     includeCalendar: Bool = true) -> [DateInterval] {
        let req = NSFetchRequest<TaskBlock>(entityName: "TaskBlock")
        req.predicate = NSPredicate(format: "isCompleted == NO AND startTime >= %@ AND startTime < %@",
                                    from.addingTimeInterval(-12 * 3600) as NSDate, to as NSDate)
        return ((try? context.fetch(req)) ?? []).compactMap { task in
            guard includeCalendar || !task.isFromCalendar else { return nil }
            guard let s = task.startTime else { return nil }
            let interval = DateInterval(start: s, duration: TimeInterval(max(task.durationMinutes, 5)) * 60)
            return interval.end > from ? interval : nil
        }
    }

    /// The taken ranges as the model reads them — times only, and only of
    /// the user's own tasks (see `busy(…includeCalendar:)`). What the blocks
    /// ARE never leaves the phone.
    static func describe(_ busy: [DateInterval], days: [Date]) -> String {
        let cal = Calendar.current
        let dayF = DateFormatter()
        dayF.locale = Locale(identifier: "en_US_POSIX")
        dayF.dateFormat = "yyyy-MM-dd (EEEE)"
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "HH:mm"
        return days.map { day in
            let ranges = busy
                .filter { cal.isDate($0.start, inSameDayAs: day) }
                .sorted { $0.start < $1.start }
                .map { "\(clock.string(from: $0.start))–\(clock.string(from: $0.end))" }
            return "\(dayF.string(from: day)): " + (ranges.isEmpty ? "nothing yet" : ranges.joined(separator: ", "))
        }.joined(separator: "\n")
    }
}

extension PlannedTask {
    /// The placement request for a task the user gave no time to.
    func slotRequest(minutes: Int) -> SlotFinder.Request {
        SlotFinder.Request(
            minutes: minutes,
            suggested: suggestedTime.flatMap(DayBuilder.parseHM),
            part: bestTime.flatMap { SlotFinder.DayPart(rawValue: $0.lowercased()) },
            effort: effort.flatMap { SlotFinder.Effort(rawValue: $0.lowercased()) }
        )
    }
}
