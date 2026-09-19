import Testing
import Foundation
@testable import Tempa___Visual_Planner

/// A task nobody gave a time to must land in a gap — never on top of what's
/// already on the day (the user's tasks, their calendar) — and in the part
/// of the day that suits it.
@MainActor
struct SlotFinderTests {
    private let cal = Calendar.current
    /// A fixed future day, so "now" never interferes unless a test wants it to.
    private var day: Date { cal.date(from: DateComponents(year: 2031, month: 3, day: 12))! }

    private func at(_ h: Int, _ m: Int = 0) -> Date {
        cal.date(bySettingHour: h, minute: m, second: 0, of: day)!
    }
    private func block(_ h: Int, _ m: Int = 0, minutes: Int) -> DateInterval {
        DateInterval(start: at(h, m), duration: TimeInterval(minutes) * 60)
    }
    private func rhythm(dip: Int? = 15) -> SlotFinder.Rhythm {
        SlotFinder.Rhythm(wake: at(7, 30), dip: dip.map { at($0) })
    }
    /// "Now" is the evening before: the whole target day is open.
    private var eveBefore: Date { at(7, 30).addingTimeInterval(-12 * 3600) }

    private func overlaps(_ start: Date, _ minutes: Int, _ busy: [DateInterval]) -> Bool {
        let end = start.addingTimeInterval(TimeInterval(minutes) * 60)
        return busy.contains { $0.start < end && $0.end > start }
    }

    @Test func heavyTaskGoesToTheMorningAndAroundMeetings() {
        let busy = [block(8, 15, minutes: 60), block(10, minutes: 30)]
        let start = SlotFinder.place(.init(minutes: 60, suggested: nil, part: nil, effort: .high),
                                     on: day, now: eveBefore, rhythm: rhythm(), busy: busy)
        #expect(!overlaps(start, 60, busy))
        #expect(SlotFinder.window(.morning, on: day, rhythm: rhythm()).contains(start))
    }

    @Test func heavyTaskStaysOutOfTheEnergyDip() {
        // The morning is one solid meeting: the heavy task must go later —
        // but not into the 15:00 dip.
        let busy = [block(8, minutes: 270)]
        let start = SlotFinder.place(.init(minutes: 90, suggested: nil, part: nil, effort: .high),
                                     on: day, now: eveBefore, rhythm: rhythm(), busy: busy)
        let dip = DateInterval(start: at(15), duration: 90 * 60)
        #expect(!overlaps(start, 90, busy))
        #expect(!overlaps(start, 90, [dip]))
    }

    @Test func lightTaskLandsInTheDip() {
        let start = SlotFinder.place(.init(minutes: 15, suggested: nil, part: nil, effort: .low),
                                     on: day, now: eveBefore, rhythm: rhythm(), busy: [])
        #expect(start == at(15))
    }

    @Test func modelSuggestionIsKeptOnlyWhenItIsReallyFree() {
        let busy = [block(19, minutes: 60)]
        let free = SlotFinder.place(.init(minutes: 30, suggested: (18, 0), part: .evening, effort: .low),
                                    on: day, now: eveBefore, rhythm: rhythm(), busy: busy)
        #expect(free == at(18))

        let taken = SlotFinder.place(.init(minutes: 30, suggested: (19, 15), part: .evening, effort: .low),
                                     on: day, now: eveBefore, rhythm: rhythm(), busy: busy)
        #expect(!overlaps(taken, 30, busy))
        #expect(SlotFinder.window(.evening, on: day, rhythm: rhythm()).contains(taken))
    }

    @Test func nothingIsPlacedInThePast() {
        let now = at(16, 40)
        let start = SlotFinder.place(.init(minutes: 30, suggested: (9, 0), part: .morning, effort: .high),
                                     on: day, now: now, rhythm: rhythm(), busy: [])
        #expect(start > now)
    }

    @Test func severalTasksNeverStack() {
        var busy = [block(9, minutes: 60), block(13, minutes: 45)]
        var placed: [(Date, Int)] = []
        for minutes in [60, 30, 45, 20, 90] {
            let s = SlotFinder.place(.init(minutes: minutes, suggested: nil, part: nil, effort: .medium),
                                     on: day, now: eveBefore, rhythm: rhythm(), busy: busy)
            #expect(!overlaps(s, minutes, busy))
            busy.append(DateInterval(start: s, duration: TimeInterval(minutes) * 60))
            placed.append((s, minutes))
        }
        #expect(placed.count == 5)
    }

    @Test func aVagueTimeSlidesToTheNearestGap() {
        // "This evening" → 19:00, but 19:00–20:00 is taken.
        let busy = [block(19, minutes: 60)]
        let start = SlotFinder.nearestFree(to: at(19), minutes: 30, now: eveBefore, busy: busy)
        #expect(!overlaps(start, 30, busy))
        #expect(start >= at(19) && start <= at(22))
    }

    @Test func aFullDayQueuesTasksInsteadOfStackingThem() {
        // Nothing free from the morning until late at night: the tasks line
        // up behind the last block, one after another — never on one minute.
        var busy = [DateInterval(start: at(6), end: at(23, 30))]
        var starts: [Date] = []
        for _ in 0..<3 {
            let s = SlotFinder.place(.init(minutes: 30, suggested: nil, part: nil, effort: nil),
                                     on: day, now: eveBefore, rhythm: rhythm(), busy: busy)
            #expect(!overlaps(s, 30, busy))
            busy.append(DateInterval(start: s, duration: 30 * 60))
            starts.append(s)
        }
        #expect(Set(starts).count == 3)
        #expect(starts[0] >= at(23, 30))
    }

    @Test func aRepeatingTaskGetsATimeFreeOnEveryOneOfItsDays() {
        // 09:00 is free on day one but taken on day two: a task repeating for
        // two days must not be given 09:00.
        let nextDay = cal.date(byAdding: .day, value: 1, to: at(9))!
        let busy = [DateInterval(start: at(8), duration: 45 * 60),
                    DateInterval(start: nextDay, duration: 60 * 60)]
        let taken = SlotFinder.projecting(busy, onto: day, repeatDays: 2)
        let start = SlotFinder.place(.init(minutes: 30, suggested: (9, 0), part: .morning, effort: .medium),
                                     on: day, now: eveBefore, rhythm: rhythm(), busy: taken)
        #expect(!overlaps(start, 30, [DateInterval(start: at(9), duration: 60 * 60)]))
        #expect(!overlaps(start, 30, busy))
    }
}
