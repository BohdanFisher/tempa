import Foundation
import EventKit
import CoreData
import Observation
import SwiftUI
import UIKit

/// Mirrors the user's calendars into Tempa, one way: what is in the calendar
/// shows up on the day as a block.
///
/// Two doors, one mirror:
///   · the phone's own calendars (EventKit) — iCloud and every account added
///     to the iPhone, one permission, no sign-in;
///   · a Google account signed in right here (`GoogleCalendar`) — for people
///     who live in the Google Calendar app and never added the account to iOS.
/// Both produce `CalendarEvent`s with the same kind of key, so an event that
/// is visible through both doors is still one block.
///
/// Nothing about an event goes to analytics or to the AI — not its title and
/// not even its time: prompts are built from the user's own tasks only, and
/// fitting around calendar blocks happens on the phone (SlotFinder).
///
/// A mirrored event is a plain TaskBlock tagged in `notes`
/// ("tempa:cal:<stable key>") — no schema change, so CloudKit needs no
/// migration. Rules of the mirror:
///   · created once, then left alone unless the EVENT changes in the calendar
///     (a block the user dragged elsewhere in Tempa stays where they put it);
///   · deleted in Tempa → stays deleted (remembered, never re-imported);
///   · deleted or declined in the calendar → removed here, if still ahead and
///     not ticked off — but only what THIS device has itself seen live, and
///     only on the word of a source we actually heard from: a Google fetch
///     that failed is never read as "everything is gone", and a second
///     device that can't see a calendar never removes the first one's blocks;
///   · all-day events are skipped — they are a date, not a block of time.
@MainActor @Observable
final class CalendarSync {
    static let shared = CalendarSync()

    nonisolated static let notePrefix = "tempa:cal:"
    /// How far ahead the mirror looks.
    static let horizonDays = 14
    /// Calendar ids from Google carry this prefix in the excluded list and in
    /// the picker, so the two doors can never collide.
    static let googleCalendarPrefix = "g:"

    nonisolated private enum Keys {
        static let enabled = "calendarSyncEnabled"
        static let excluded = "calendarSyncExcludedCalendars"
        static let known = "calendarSyncKnown"           // key → fingerprint
        static let dismissed = "calendarSyncDismissed"   // keys the user deleted in Tempa
        static let alarmed = "calendarSyncAlarmed"       // keys whose event rings on its own
        static let googleCache = "calendarSyncGoogleCache"   // the last successful Google fetch
        static let googleKeys = "calendarSyncGoogleKeys"     // keys that fetch contained
        static let googleSeenCalendars = "calendarSyncGoogleSeenCalendars"   // ids already offered once
    }

    /// Every UserDefaults key of the mirror — for the dev "factory reset".
    nonisolated static let allDefaultsKeys = [
        Keys.enabled, Keys.excluded, Keys.known, Keys.dismissed, Keys.alarmed,
        Keys.googleCache, Keys.googleKeys, Keys.googleSeenCalendars,
    ]

    /// Mirrored blocks whose calendar event already carries an alert. The
    /// Calendar app will ring for those — a second nudge from Tempa for the
    /// same meeting is exactly the noise it promises not to make.
    nonisolated static func ownAlarmKeys() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Keys.alarmed) ?? [])
    }

    private let store = EKEventStore()
    private let google = GoogleCalendar.shared
    private var observingStore = false
    private var observingDeletes = false
    /// True while the mirror itself is writing — its own deletions are not
    /// the user's.
    private var isMirroring = false
    /// Bumped by every Google fetch; a fetch that comes back to find a newer
    /// one started throws its result away.
    private var googleFetchGeneration = 0

    /// The user's switch for the phone's own calendars. Access can still be
    /// revoked in iOS Settings — see `appleActive`.
    var appleEnabled: Bool = UserDefaults.standard.bool(forKey: Keys.enabled) {
        didSet { UserDefaults.standard.set(appleEnabled, forKey: Keys.enabled) }
    }

    /// The last successful Google fetch, kept across launches. It is what the
    /// mirror trusts about Google until the next fetch succeeds: nil means
    /// "never heard from Google", and then nothing of Google's is removed.
    private var googleEvents: [CalendarEvent]? = {
        guard let data = UserDefaults.standard.data(forKey: Keys.googleCache) else { return nil }
        return try? JSONDecoder().decode([CalendarEvent].self, from: data)
    }()

    private init() {}

    // MARK: - Access

    var authorization: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    var hasAccess: Bool { authorization == .fullAccess }
    /// iOS only asks once; after a "no" the way back is the Settings app.
    var isDenied: Bool { authorization == .denied || authorization == .restricted || authorization == .writeOnly }
    var appleActive: Bool { appleEnabled && hasAccess }
    var googleActive: Bool { google.isConnected }
    var isActive: Bool { appleActive || googleActive }

    /// Shows the system prompt (first time) and reports the outcome.
    func requestAccess() async -> Bool {
        if hasAccess { return true }
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        if granted { store.reset() }   // a store created before the grant sees nothing until reset
        return granted
    }

    // MARK: - Calendars

    struct CalendarInfo: Identifiable {
        let id: String
        let title: String
        let account: String
        let color: CGColor?
        var isIncluded: Bool
    }

    private var excludedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Keys.excluded) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Keys.excluded) }
    }

    private func appleCalendars() -> [EKCalendar] {
        guard appleActive else { return [] }
        // Birthdays and holiday subscriptions are all-day anyway and would
        // only be noise in the list.
        return store.calendars(for: .event).filter { $0.type != .birthday && $0.type != .subscription }
    }

    /// Every calendar the user can switch on or off, both doors.
    func calendars() -> [CalendarInfo] {
        let excluded = excludedIDs
        let apple = appleCalendars().map {
            CalendarInfo(id: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "",
                         color: $0.cgColor, isIncluded: !excluded.contains($0.calendarIdentifier))
        }
        let fromGoogle = googleActive ? google.calendars.map { ref -> CalendarInfo in
            let id = Self.googleCalendarPrefix + ref.id
            return CalendarInfo(id: id, title: ref.title, account: google.email ?? "Google",
                                color: ref.colorHex.map { UIColor(Color(hex: $0)).cgColor },
                                isIncluded: !excluded.contains(id))
        } : []
        return (apple + fromGoogle).sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    func setIncluded(_ included: Bool, calendarID: String) {
        var set = excludedIDs
        if included { set.remove(calendarID) } else { set.insert(calendarID) }
        excludedIDs = set
    }

    // MARK: - Reading events

    /// Timed events in [from, to) from the phone's included calendars.
    private func appleEvents(from: Date, to: Date) -> [CalendarEvent] {
        let excluded = excludedIDs
        let cals = appleCalendars().filter { !excluded.contains($0.calendarIdentifier) }
        guard !cals.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: cals)
        return store.events(matching: predicate).compactMap { event in
            guard !event.isAllDay, event.status != .canceled,
                  let start = event.startDate, let end = event.endDate,
                  start >= from, end > start else { return nil }
            // An invitation the user said no to is not part of their day.
            let declined = event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
            guard !declined else { return nil }
            let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return CalendarEvent(
                source: .apple, key: Self.key(of: event),
                title: title.isEmpty ? String(localized: "Calendar event", bundle: .appLanguage) : title,
                start: start, end: end, ringsOnItsOwn: event.hasAlarms,
                category: CalendarEvent.category(
                    calendarName: "\(event.calendar?.title ?? "") \(event.calendar?.source?.title ?? "")",
                    isExchange: event.calendar?.source?.sourceType == .exchange)
            )
        }
    }

    /// Both doors, merged. The same event seen twice collapses on its key —
    /// and, as a net under that, on "same title at the same time".
    private func liveEvents(from: Date, to: Date) -> [CalendarEvent] {
        let apple = appleEvents(from: from, to: to)
        guard googleActive, let cached = googleEvents else { return apple }
        var seenKeys = Set(apple.map(\.key))
        let seenLooks = Set(apple.map(\.fingerprint))
        var merged = apple
        for event in cached where event.start >= from && event.start < to {
            guard !seenKeys.contains(event.key), !seenLooks.contains(event.fingerprint) else { continue }
            seenKeys.insert(event.key)
            merged.append(event)
        }
        return merged
    }

    private func dayBounds(_ day: Date) -> (Date, Date)? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return nil }
        return (start, end)
    }

    /// One day as drafts, for the funnel's preview of the laid-out day —
    /// nothing is written to the store until purchase.
    func drafts(on day: Date) -> [DayBuilder.Draft] {
        guard let (start, end) = dayBounds(day) else { return [] }
        return liveEvents(from: start, to: end).map { event in
            DayBuilder.Draft(title: event.title, category: event.category, icon: Self.icon,
                             start: event.start, minutes: event.minutes,
                             group: nil, notes: Self.notePrefix + event.key)
        }
    }

    /// What's taken between two instants, straight from the calendars — for
    /// the funnel, where nothing is in the store yet.
    func busy(from: Date, to: Date) -> [DateInterval] {
        liveEvents(from: from, to: to).map { DateInterval(start: $0.start, end: max($0.end, $0.start)) }
    }

    /// How many timed events lie in the next `days` days — the number the
    /// connect screen shows back ("12 events in the next 7 days").
    func upcomingCount(days: Int = 7) -> Int {
        let start = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: start) else { return 0 }
        return liveEvents(from: start, to: end).count
    }

    // MARK: - Google

    /// Fetches the Google side of the window and keeps it. Quiet on failure:
    /// the previous fetch stays the truth until a new one succeeds.
    @discardableResult
    func refreshGoogle() async -> Bool {
        guard googleActive else { return false }
        let from = Calendar.current.startOfDay(for: Date())
        guard let to = Calendar.current.date(byAdding: .day, value: Self.horizonDays, to: from) else { return false }
        googleFetchGeneration += 1
        let generation = googleFetchGeneration
        do {
            let refs = try await google.loadCalendars()
            // A calendar the user keeps unticked in Google Calendar (a
            // colleague's, a shared room) starts switched off here too. Only
            // the first time it is seen — after that the picker decides.
            var seen = Set(UserDefaults.standard.stringArray(forKey: Keys.googleSeenCalendars) ?? [])
            var excluded = excludedIDs
            for ref in refs where !seen.contains(ref.id) {
                seen.insert(ref.id)
                if !ref.isShownInGoogle { excluded.insert(Self.googleCalendarPrefix + ref.id) }
            }
            excludedIDs = excluded
            UserDefaults.standard.set(Array(seen), forKey: Keys.googleSeenCalendars)

            var wanted: [String: String] = [:]
            for ref in refs where !excluded.contains(Self.googleCalendarPrefix + ref.id) { wanted[ref.id] = ref.title }
            let events = try await google.events(from: from, to: to, calendarIDs: wanted)
            // A newer fetch started while this one was out (a second toggle
            // in the picker): its answer wins, this one is already stale.
            guard generation == googleFetchGeneration, googleActive else { return false }
            googleEvents = events
            if let data = try? JSONEncoder().encode(events) { UserDefaults.standard.set(data, forKey: Keys.googleCache) }
            return true
        } catch {
            #if DEBUG
            print("[Tempa] Google Calendar fetch failed:", error)
            #endif
            return false
        }
    }

    /// Signs the Google account out and takes its upcoming blocks with it.
    func disconnectGoogle(from context: NSManagedObjectContext) async {
        await google.disconnect()
        forgetGoogleCache()
        sync(into: context)
    }

    private func forgetGoogleCache() {
        googleFetchGeneration += 1   // anything still in flight is void
        googleEvents = nil
        UserDefaults.standard.removeObject(forKey: Keys.googleCache)
        UserDefaults.standard.removeObject(forKey: Keys.googleSeenCalendars)
        excludedIDs = excludedIDs.filter { !$0.hasPrefix(Self.googleCalendarPrefix) }
    }

    /// The whole round: mirror what is known right now, then ask Google and
    /// mirror again. Called on every return to the app.
    func refresh(into context: NSManagedObjectContext) async {
        sync(into: context)
        if await refreshGoogle() { sync(into: context) }
    }

    // MARK: - Mirror

    /// Brings the store in line with the calendars. Cheap and idempotent:
    /// called on connect, on every return to the app, and whenever iOS says
    /// the calendar database changed.
    @discardableResult
    func sync(into context: NSManagedObjectContext) -> Int {
        // Signed out on Google's side (access withdrawn there): what was
        // cached belongs to an account that is no longer connected.
        if !googleActive, googleEvents != nil { forgetGoogleCache() }

        var known = UserDefaults.standard.dictionary(forKey: Keys.known) as? [String: String] ?? [:]
        // Never connected (or fully cleaned up after disconnecting): nothing to do.
        guard isActive || !known.isEmpty else { return 0 }
        start(context)
        // What THIS device had seen live before this round. It is the licence
        // to change a block: a block mirrored by another device (arrived via
        // iCloud) or carried forward from a past day is not ours to touch.
        let knownBefore = known
        isMirroring = true
        defer { isMirroring = false }

        let cal = Calendar.current
        let now = Date()
        let from = cal.startOfDay(for: now)
        guard let to = cal.date(byAdding: .day, value: Self.horizonDays, to: from) else { return 0 }

        var liveByKey: [String: CalendarEvent] = [:]
        for event in liveEvents(from: from, to: to) { liveByKey[event.key] = event }

        // What Google's side of the mirror can be trusted about. Not
        // connected → it has nothing, and that IS known. Connected but never
        // fetched → unknown: leave its blocks exactly as they are.
        let googleIsKnown = !googleActive || googleEvents != nil
        let lastGoogleKeys = Set(UserDefaults.standard.stringArray(forKey: Keys.googleKeys) ?? [])

        let req = NSFetchRequest<TaskBlock>(entityName: "TaskBlock")
        req.predicate = NSPredicate(format: "notes BEGINSWITH %@ AND startTime >= %@",
                                    Self.notePrefix, from as NSDate)
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let mirrored = (try? context.fetch(req)) ?? []

        var taskByKey: [String: TaskBlock] = [:]
        for task in mirrored {
            guard let key = task.notes.map({ String($0.dropFirst(Self.notePrefix.count)) }) else { continue }
            guard let kept = taskByKey[key] else { taskByKey[key] = task; continue }
            // Two devices mirrored the same event before they met in iCloud.
            // The older block stays — unless only the newer one was ticked off.
            if task.isCompleted && !kept.isCompleted {
                context.delete(kept)
                taskByKey[key] = task
            } else {
                context.delete(task)
            }
        }

        // Blocks the user deleted in Tempa — recorded at the moment of the
        // deletion (see `start`), never guessed from a block being absent:
        // absent can also mean "another device removed it".
        var dismissed = Set(UserDefaults.standard.stringArray(forKey: Keys.dismissed) ?? [])

        // The rating prompt waits for the first task the USER makes. (Restored,
        // not cleared: the first-day writer holds the same flag around us.)
        let wasWriting = ReviewPrompt.isWritingDemoPlan
        ReviewPrompt.isWritingDemoPlan = true
        defer { ReviewPrompt.isWritingDemoPlan = wasWriting }

        var created = 0
        for (key, event) in liveByKey {
            if let task = taskByKey[key] {
                // Follow the calendar only when the EVENT moved — never undo
                // what the user rearranged inside Tempa, and never "correct"
                // a block this device is only meeting for the first time.
                if let before = knownBefore[key], before != event.fingerprint, !task.isCompleted {
                    apply(event, to: task)
                }
            } else if !dismissed.contains(key) {
                let task = TaskBlock(context: context)
                task.id = UUID()
                task.createdAt = now
                task.notes = Self.notePrefix + key
                task.category = event.category
                task.iconName = Self.icon
                apply(event, to: task)
                created += 1
            }
            known[key] = event.fingerprint
        }

        // Cancelled, declined or deleted in the calendar → gone here too,
        // unless it already happened or was ticked off (that's history), or
        // it came from Google and Google hasn't been heard from.
        for (key, task) in taskByKey where liveByKey[key] == nil {
            guard knownBefore[key] != nil else { continue }   // never seen live here — not ours to remove
            guard !task.isCompleted, (task.startTime ?? .distantPast) > now else { continue }
            if !googleIsKnown && lastGoogleKeys.contains(key) { continue }
            context.delete(task)
        }

        // Only keep memory of what is still inside the window (and, while
        // Google is silent, of what it showed last time).
        let keepSilentGoogle: (String) -> Bool = { !googleIsKnown && lastGoogleKeys.contains($0) }
        known = known.filter { liveByKey[$0.key] != nil || keepSilentGoogle($0.key) }
        dismissed = dismissed.filter { liveByKey[$0] != nil || keepSilentGoogle($0) }
        UserDefaults.standard.set(known, forKey: Keys.known)
        UserDefaults.standard.set(Array(dismissed), forKey: Keys.dismissed)
        UserDefaults.standard.set(liveByKey.filter { $0.value.ringsOnItsOwn }.map(\.key), forKey: Keys.alarmed)
        if googleIsKnown {
            UserDefaults.standard.set(liveByKey.filter { $0.value.source == .google }.map(\.key), forKey: Keys.googleKeys)
        }

        if context.hasChanges { try? context.save() }
        return created
    }

    /// Switching the phone's calendars off takes their upcoming blocks with
    /// it (a connected Google account keeps its own); what was already done
    /// stays in the history.
    func disconnectApple(from context: NSManagedObjectContext) {
        appleEnabled = false
        excludedIDs = excludedIDs.filter { $0.hasPrefix(Self.googleCalendarPrefix) }
        sync(into: context)
    }

    private func apply(_ event: CalendarEvent, to task: TaskBlock) {
        task.title = event.title
        task.startTime = event.start
        task.durationMinutes = Int32(event.minutes)
    }

    /// Call once at launch. Two things are watched: the phone's calendar
    /// database (re-mirror when it changes), and the user deleting a mirrored
    /// block in Tempa — caught as the save goes out, while the block can
    /// still be read, and only on the view context: a deletion arriving from
    /// another device through iCloud never passes through here.
    func start(_ context: NSManagedObjectContext) {
        if !observingDeletes {
            observingDeletes = true
            NotificationCenter.default.addObserver(forName: .NSManagedObjectContextWillSave, object: context, queue: nil) { _ in
                MainActor.assumeIsolated {
                    let sync = CalendarSync.shared
                    guard !sync.isMirroring else { return }
                    let keys = context.deletedObjects.compactMap { ($0 as? TaskBlock)?.notes }
                        .filter { $0.hasPrefix(CalendarSync.notePrefix) }
                        .map { String($0.dropFirst(CalendarSync.notePrefix.count)) }
                    guard !keys.isEmpty else { return }
                    let dismissed = Set(UserDefaults.standard.stringArray(forKey: Keys.dismissed) ?? []).union(keys)
                    UserDefaults.standard.set(Array(dismissed), forKey: Keys.dismissed)
                }
            }
        }
        if appleActive, !observingStore {
            observingStore = true
            NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
                MainActor.assumeIsolated {
                    _ = CalendarSync.shared.sync(into: context)
                }
            }
        }
    }

    // MARK: - Event → block

    private static let icon = "calendar"

    /// The iCalendar UID (the same string Google calls iCalUID, so both doors
    /// agree), plus the original start for one occurrence of a repeating
    /// event. A one-off event keeps its key when it is moved — the block
    /// moves with it instead of being replaced.
    private static func key(of event: EKEvent) -> String {
        let base = event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? UUID().uuidString
        guard event.hasRecurrenceRules || event.isDetached else { return base }
        let occurrence = event.occurrenceDate ?? event.startDate ?? Date()
        return "\(base)|\(Int(occurrence.timeIntervalSince1970 / 60))"
    }
}

extension TaskBlock {
    /// True for a block mirrored from the phone's calendar.
    var isFromCalendar: Bool { notes?.hasPrefix(CalendarSync.notePrefix) == true }
}
