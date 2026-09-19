import Testing
import Foundation
@testable import Tempa___Visual_Planner

/// Google's JSON → blocks. What must never become a block: an all-day entry,
/// a cancelled event, an invitation the user declined, a "working location"
/// marker. And the key has to match the one EventKit would build for the
/// same event, or people with Google on both doors see everything twice.
@MainActor
struct GoogleCalendarTests {
    private func event(_ fields: [String: Any]) -> [String: Any] {
        var base: [String: Any] = [
            "id": "abc", "iCalUID": "abc@google.com", "summary": "Standup", "status": "confirmed",
            "start": ["dateTime": "2031-03-12T09:00:00+02:00"],
            "end": ["dateTime": "2031-03-12T09:30:00+02:00"],
        ]
        for (k, v) in fields { base[k] = v }
        return base
    }

    @Test func aPlainEventBecomesABlock() throws {
        let parsed = GoogleCalendar.parseEvents([event([:])], calendarName: "Work")
        let block = try #require(parsed.first)
        #expect(parsed.count == 1)
        #expect(block.title == "Standup")
        #expect(block.minutes == 30)
        #expect(block.key == "abc@google.com")
        #expect(block.category == "work")
        #expect(block.source == .google)
    }

    @Test func whatIsNotPartOfTheDayIsLeftOut() {
        let items: [[String: Any]] = [
            event(["status": "cancelled"]),
            event(["start": ["date": "2031-03-12"], "end": ["date": "2031-03-13"]]),   // all-day
            event(["eventType": "workingLocation"]),
            event(["attendees": [["self": true, "responseStatus": "declined"]]]),
        ]
        #expect(GoogleCalendar.parseEvents(items, calendarName: "Home").isEmpty)
    }

    @Test func anInvitationStillPendingStays() {
        let items = [event(["attendees": [["self": true, "responseStatus": "needsAction"],
                                          ["self": false, "responseStatus": "declined"]]])]
        #expect(GoogleCalendar.parseEvents(items, calendarName: "Home").count == 1)
    }

    @Test func oneOccurrenceOfARepeatingEventIsKeyedByItsOriginalStart() throws {
        // Moved from 09:00 to 11:00 for this one day: the key keeps pointing
        // at the ORIGINAL slot, exactly like EventKit's occurrenceDate.
        let moved = event([
            "recurringEventId": "series1",
            "originalStartTime": ["dateTime": "2031-03-12T09:00:00+02:00"],
            "start": ["dateTime": "2031-03-12T11:00:00+02:00"],
            "end": ["dateTime": "2031-03-12T11:30:00+02:00"],
        ])
        let block = try #require(GoogleCalendar.parseEvents([moved], calendarName: "Home").first)
        let original = try #require(ISO8601DateFormatter().date(from: "2031-03-12T09:00:00+02:00"))
        #expect(block.key == "abc@google.com|\(Int(original.timeIntervalSince1970 / 60))")
    }

    @Test func holidayAndBirthdayFeedsAreNotOffered() {
        let refs = GoogleCalendar.parseCalendars([
            ["id": "me@gmail.com", "summary": "me@gmail.com", "primary": true],
            ["id": "en.ukrainian#holiday@group.v.calendar.google.com", "summary": "Holidays", "selected": true],
            ["id": "addressbook#contacts@group.v.calendar.google.com", "summary": "Birthdays", "selected": true],
            ["id": "team@group.calendar.google.com", "summary": "Team", "summaryOverride": "My team", "selected": true],
        ])
        #expect(refs.map(\.id) == ["me@gmail.com", "team@group.calendar.google.com"])
        #expect(refs.last?.title == "My team")
    }

    @Test func whatIsUntickedInGoogleStartsSwitchedOffHere() {
        // Google leaves "selected" out when a calendar is unticked — a
        // colleague's calendar must not flood the day by default.
        let refs = GoogleCalendar.parseCalendars([
            ["id": "me@gmail.com", "summary": "me@gmail.com", "primary": true],
            ["id": "family@group.calendar.google.com", "summary": "Family", "selected": true],
            ["id": "colleague@company.com", "summary": "Colleague"],
        ])
        #expect(refs.map(\.isShownInGoogle) == [true, true, false])
    }

    @Test func theRedirectSchemeIsTheClientIDReversed() {
        #expect(GoogleCalendar.redirectScheme(for: "123-abc.apps.googleusercontent.com")
                == "com.googleusercontent.apps.123-abc")
    }

    @Test func thePKCEChallengeMatchesTheRFCExample() {
        // RFC 7636, appendix B.
        #expect(GoogleCalendar.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
                == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
}
