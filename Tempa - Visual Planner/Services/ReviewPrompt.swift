import CoreData
import Observation

/// Asks for an App Store rating right after the very first task a person
/// creates — the one moment we know Tempa has just done its job for them.
///
/// Apple owns the dialog end to end: the wording is system-provided and
/// localized by iOS into the device's language, and iOS decides whether to
/// actually show it (roughly three prompts per year per device). We only say
/// "now is a good moment". Nothing here nags: it fires once per install and
/// never again, and a person who ignores it is never asked twice.
///
/// Why a save observer rather than a call at each site: tasks are created from
/// seven different places (add sheet, breakdown, day plan, duplicate, voice…),
/// and an eighth will be added one day. One choke point can't be forgotten.
@MainActor
@Observable
final class ReviewPrompt {
    static let shared = ReviewPrompt()

    /// Rotated from "reviewPromptAsked": onboarding's late "first win" screen
    /// (removed) set that flag while asking at the wrong moment, which would
    /// have silenced this — the intended — ask forever on every install that
    /// went through it. iOS rate-limits the dialog, so a second ask is safe.
    private static let askedKey = "reviewPromptAskedAfterFirstTask"

    /// Set once a first task lands; MainTabView watches this and does the ask.
    /// Stays true until the prompt is actually delivered, so a task created
    /// just before backgrounding still gets its moment on the next return.
    private(set) var shouldAsk = false

    /// Onboarding's demo plan is written FOR the user, not BY them — it must
    /// never count as their first task. Set around DemoPlanStash.materialize.
    static var isWritingDemoPlan = false

    private var asked: Bool {
        get { UserDefaults.standard.bool(forKey: Self.askedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.askedKey) }
    }

    /// Not private so tests can drive a fresh instance instead of the shared
    /// one (whose "already asked" flag would leak between test cases).
    init() {}

    /// Watch local saves for the first inserted task. Only the view context is
    /// observed, so CloudKit imports from another device never trigger a
    /// prompt — a synced task isn't something the person just did here.
    func startObserving(_ context: NSManagedObjectContext) {
        guard !asked else { return }
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: context,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                self?.handleSave(note)
            }
        }
    }

    private func handleSave(_ note: Notification) {
        guard !asked, !shouldAsk, !Self.isWritingDemoPlan else { return }
        let inserted = note.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? []
        guard inserted.contains(where: { $0 is TaskBlock }) else { return }
        shouldAsk = true
    }

    /// Called once the system prompt has been requested — never ask again on
    /// this install, and stop listening.
    func markAsked() {
        shouldAsk = false
        asked = true
    }
}
