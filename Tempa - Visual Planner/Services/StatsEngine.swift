import Foundation
import CoreData

/// Real usage statistics computed straight from Core Data — task completions,
/// planned load and focus history. No estimates, no placeholder numbers.
enum StatsEngine {

    // MARK: - Day battery (time + load resource for today)

    struct DayBattery {
        let percent: Int                // % of the waking day still ahead
        let remainingMin: Int           // minutes left until the day "ends"
        let reservedMin: Int            // minutes of today's unfinished tasks
        let freeMin: Int                // remaining − reserved (negative = overbooked)
        let capacityMin: Int            // full waking window
        let remainingFrac: Double       // 0…1 of capacity
        let freeFracOfRemaining: Double // 0…1, how much of the remaining bar is free
    }

    /// The waking day runs from the user's wake time for ~16 hours.
    /// Battery = how much of that window is still ahead; the reserved part is
    /// the summed duration of today's not-yet-completed tasks.
    static func dayBattery(wakeTime: Date, context: NSManagedObjectContext, now: Date = Date()) -> DayBattery {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: wakeTime)
        // Anchor to the most recent wake instant ≤ now. A 9:00 wake means the
        // waking window runs 9:00 → 1:00 next day, so just after midnight the
        // window started YESTERDAY — without this the battery snaps back to 100%.
        var dayStart = cal.date(bySettingHour: comps.hour ?? 7, minute: comps.minute ?? 0,
                                second: 0, of: now) ?? cal.startOfDay(for: now)
        if now < dayStart {
            dayStart = cal.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
        }
        let capacityMin = 16 * 60
        let dayEnd = dayStart.addingTimeInterval(TimeInterval(capacityMin) * 60)
        let elapsedMin = min(max(Int(now.timeIntervalSince(dayStart) / 60), 0), capacityMin)
        let remainingMin = capacityMin - elapsedMin

        // Unfinished tasks inside the waking window — including late-night ones
        // that technically fall on the next calendar day.
        let req = NSFetchRequest<TaskBlock>(entityName: "TaskBlock")
        req.predicate = NSPredicate(format: "startTime >= %@ AND startTime < %@ AND isCompleted == NO",
                                    dayStart as NSDate, dayEnd as NSDate)
        let reservedMin = ((try? context.fetch(req)) ?? []).reduce(0) { $0 + Int($1.durationMinutes) }

        let freeMin = remainingMin - reservedMin
        let remainingFrac = Double(remainingMin) / Double(capacityMin)
        let freeFrac = remainingMin > 0 ? max(0, min(1, Double(freeMin) / Double(remainingMin))) : 0

        return DayBattery(
            percent: min(max(Int((remainingFrac * 100).rounded()), 0), 100),
            remainingMin: remainingMin,
            reservedMin: reservedMin,
            freeMin: freeMin,
            capacityMin: capacityMin,
            remainingFrac: remainingFrac,
            freeFracOfRemaining: freeFrac
        )
    }

    // MARK: - Period stats (today / week / month)

    struct StatDay: Identifiable {
        var id: Date { date }
        let date: Date
        let done: Int
    }

    struct PeriodStats {
        let plannedCount: Int      // tasks scheduled in the period
        let doneCount: Int         // tasks completed in the period
        let doneMinutes: Int       // duration of those completions
        let days: [StatDay]        // per-day completion counts, oldest first
    }

    static func periodStats(daysBack: Int, context: NSManagedObjectContext, now: Date = Date()) -> PeriodStats {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        let from = cal.date(byAdding: .day, value: -(daysBack - 1), to: todayStart) ?? todayStart
        let to = cal.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart

        let plannedReq = NSFetchRequest<TaskBlock>(entityName: "TaskBlock")
        plannedReq.predicate = NSPredicate(format: "startTime >= %@ AND startTime < %@",
                                           from as NSDate, to as NSDate)
        let planned = (try? context.fetch(plannedReq)) ?? []

        let doneReq = NSFetchRequest<TaskBlock>(entityName: "TaskBlock")
        doneReq.predicate = NSPredicate(format: "completedAt >= %@ AND completedAt < %@",
                                        from as NSDate, to as NSDate)
        let done = (try? context.fetch(doneReq)) ?? []

        var perDay: [Date: Int] = [:]
        for t in done {
            guard let c = t.completedAt else { continue }
            perDay[cal.startOfDay(for: c), default: 0] += 1
        }
        let days: [StatDay] = (0..<daysBack).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: from) else { return nil }
            return StatDay(date: d, done: perDay[d] ?? 0)
        }

        return PeriodStats(
            plannedCount: planned.count,
            doneCount: done.count,
            doneMinutes: done.reduce(0) { $0 + Int($1.durationMinutes) },
            days: days
        )
    }

    // MARK: - Where the time goes (per category)

    struct CategoryStat: Identifiable {
        var id: String { category }
        let category: String
        let doneMin: Int
        let plannedMin: Int
    }

    static func categoryStats(daysBack: Int, context: NSManagedObjectContext, now: Date = Date()) -> [CategoryStat] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        let from = cal.date(byAdding: .day, value: -(daysBack - 1), to: todayStart) ?? todayStart
        let to = cal.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart

        let plannedReq = NSFetchRequest<TaskBlock>(entityName: "TaskBlock")
        plannedReq.predicate = NSPredicate(format: "startTime >= %@ AND startTime < %@",
                                           from as NSDate, to as NSDate)
        let planned = (try? context.fetch(plannedReq)) ?? []

        let doneReq = NSFetchRequest<TaskBlock>(entityName: "TaskBlock")
        doneReq.predicate = NSPredicate(format: "completedAt >= %@ AND completedAt < %@",
                                        from as NSDate, to as NSDate)
        let done = (try? context.fetch(doneReq)) ?? []

        var plannedBy: [String: Int] = [:]
        var doneBy: [String: Int] = [:]
        for t in planned { plannedBy[t.category ?? "work", default: 0] += Int(t.durationMinutes) }
        for t in done { doneBy[t.category ?? "work", default: 0] += Int(t.durationMinutes) }

        return Cat.all.map(\.0).compactMap { name in
            let p = plannedBy[name] ?? 0
            let d = doneBy[name] ?? 0
            guard p > 0 || d > 0 else { return nil }
            return CategoryStat(category: name, doneMin: d, plannedMin: p)
        }
        .sorted { max($0.doneMin, $0.plannedMin) > max($1.doneMin, $1.plannedMin) }
    }

    // MARK: - Streak & records

    struct StreakInfo {
        let current: Int           // consecutive days with ≥1 completion (today optional)
        let best: Int              // longest run ever (within the last year)
        let bestDayCount: Int      // most tasks completed in a single day
        let bestDayDate: Date?
        let last7: [Bool]          // last 7 days incl. today, oldest first
    }

    static func streak(context: NSManagedObjectContext, now: Date = Date()) -> StreakInfo {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        let from = cal.date(byAdding: .day, value: -365, to: todayStart) ?? todayStart

        let req = NSFetchRequest<TaskBlock>(entityName: "TaskBlock")
        req.predicate = NSPredicate(format: "completedAt >= %@", from as NSDate)
        let done = (try? context.fetch(req)) ?? []

        var perDay: [Date: Int] = [:]
        for t in done {
            guard let c = t.completedAt else { continue }
            perDay[cal.startOfDay(for: c), default: 0] += 1
        }
        let daysWithDone = Set(perDay.keys)

        // Current run: today counts if present, otherwise the run may end yesterday —
        // the streak isn't "lost" until the day is actually over.
        var current = 0
        var cursor = daysWithDone.contains(todayStart)
            ? todayStart
            : (cal.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart)
        while daysWithDone.contains(cursor) {
            current += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        // Longest run in the window.
        var best = 0
        var run = 0
        var day = from
        while day <= todayStart {
            if daysWithDone.contains(day) {
                run += 1
                best = max(best, run)
            } else {
                run = 0
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        best = max(best, current)

        let bestDay = perDay.max { $0.value < $1.value }

        let last7: [Bool] = (0..<7).map { i in
            guard let d = cal.date(byAdding: .day, value: -(6 - i), to: todayStart) else { return false }
            return daysWithDone.contains(d)
        }

        return StreakInfo(
            current: current,
            best: best,
            bestDayCount: bestDay?.value ?? 0,
            bestDayDate: bestDay?.key,
            last7: last7
        )
    }
}
