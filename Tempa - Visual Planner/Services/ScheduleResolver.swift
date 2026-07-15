import Foundation
import CoreData

/// Turns a parsed `TaskBreakdown.Schedule` into a concrete start `Date`.
///
/// The model already resolved the user's words into a concrete `time` (e.g.
/// "після роботи" → 18:00). We honor exact clock times verbatim, and for
/// approximate/contextual phrases we keep the model's time but nudge it to the
/// next free hour-slot if that hour is already taken.
///
/// Returns nil when the user gave no time at all — the sheet keeps its default.
enum ScheduleResolver {

    static func resolve(_ schedule: TaskBreakdown.Schedule?, context: NSManagedObjectContext) -> Date? {
        guard let s = schedule, s.hasTime == true, let time = parseTime(s.time) else { return nil }

        let cal = Calendar.current
        let now = Date()
        let day = parseDate(s.date) ?? cal.startOfDay(for: now)

        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = time.hour
        comps.minute = time.minute
        guard let base = cal.date(from: comps) else { return nil }

        // Exact clock time → honor exactly, no shifting.
        if s.precise == true { return base }

        // Approximate/contextual → keep the hour, but skip to the next free one if busy.
        return firstFreeHour(from: base, now: now, context: context)
    }

    /// First hour at/after `base` (same day) that isn't already taken and isn't in the past.
    /// Falls back to `base` if nothing is free.
    private static func firstFreeHour(from base: Date, now: Date, context: NSManagedObjectContext) -> Date {
        let cal = Calendar.current
        let busy = busyIntervals(on: base, context: context)
        let baseHour = cal.component(.hour, from: base)

        guard var candidate = cal.date(bySettingHour: baseHour, minute: 0, second: 0, of: base) else { return base }
        let dayEnd = cal.date(bySettingHour: 23, minute: 0, second: 0, of: base) ?? base

        while candidate <= dayEnd {
            let slotEnd = candidate.addingTimeInterval(3600)
            let isPast = candidate.addingTimeInterval(60) < now      // small grace so "now" still counts
            let overlaps = busy.contains { $0.start < slotEnd && $0.end > candidate }
            if !isPast && !overlaps { return candidate }
            candidate = candidate.addingTimeInterval(3600)
        }
        return base   // whole rest of day busy/past → just use the model's anchor
    }

    /// Combine a parsed date + time into a concrete Date, with no free-slot shifting.
    /// Returns nil when there's no usable time. Used by the day-planner.
    static func concreteStart(date: String?, time: String?) -> Date? {
        guard let t = parseTime(time) else { return nil }
        let cal = Calendar.current
        let day = parseDate(date) ?? cal.startOfDay(for: Date())
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = t.hour
        comps.minute = t.minute
        return cal.date(from: comps)
    }

    private static func busyIntervals(on day: Date, context: NSManagedObjectContext) -> [(start: Date, end: Date)] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let req = NSFetchRequest<TaskBlock>(entityName: "TaskBlock")
        req.predicate = NSPredicate(format: "startTime >= %@ AND startTime < %@", start as NSDate, end as NSDate)
        let tasks = (try? context.fetch(req)) ?? []
        return tasks.compactMap { t in
            guard let s = t.startTime else { return nil }
            return (s, s.addingTimeInterval(TimeInterval(t.durationMinutes) * 60))
        }
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty, s.lowercased() != "null" else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: s) else { return nil }
        return Calendar.current.startOfDay(for: d)
    }

    private static func parseTime(_ s: String?) -> (hour: Int, minute: Int)? {
        guard let s, !s.isEmpty, s.lowercased() != "null" else { return nil }
        let parts = s.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }
}
