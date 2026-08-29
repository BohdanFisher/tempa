import SwiftUI
import CoreData

@main
struct TempaApp: App {
    let persistenceController = PersistenceController.shared
    let subscriptionManager = SubscriptionManager.shared

    @State private var settingsStore: SettingsStore
    @AppStorage("themePreference") private var themePreference: ThemePreference = .system
    @AppStorage("appLanguage") private var appLanguageRaw = "system"
    @Environment(\.scenePhase) private var scenePhase

    init() {
        RevenueCatService.configure()
        #if DEBUG
        // "-wipe-data YES": start as a brand-new user — empties the local store
        // AND pushes the deletions to iCloud, so nothing comes back. The funnel
        // flag lives in UserDefaults, not the store, so clear it too or the
        // "new user" would boot into the hard paywall instead of onboarding.
        if UserDefaults.standard.bool(forKey: "wipe-data") {
            PersistenceController.wipeAllData()
            UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
            // Also forget that the funnel was ever completed — this very run
            // then behaves like a fresh install and boots into the funnel.
            UserDefaults.standard.removeObject(forKey: "funnelCompletedOnce")
        }
        #endif
        let context = PersistenceController.shared.container.viewContext
        _settingsStore = State(initialValue: SettingsStore(context: context))

        TaskNotifications.startObserving(context)
        ReviewPrompt.shared.startObserving(context)
        AppLanguage.current.apply()   // keep the AppleLanguages override in sync

        #if DEBUG
        if UserDefaults.standard.bool(forKey: "test-cloud-key")
            || UserDefaults.standard.bool(forKey: "remove-god-nail") {
            // "-test-cloud-key YES": rehearse the App Store path — no dev key,
            // empty Keychain, the key must arrive from the CloudKit public
            // record exactly like on a real user's phone.
            // "-remove-god-nail YES": un-owner a device — leave its Keychain
            // the way a production phone has it, so no dev key either.
            ClaudeAPIClient().wipeStoredAPIKey()
        } else {
            ClaudeAPIClient().setupDevKey()
        }
        #endif
        // Real installs have no dev key — warm it from CloudKit now so the
        // user's first AI request doesn't also pay the fetch round-trip.
        // No-op when the Keychain already holds one; failures self-heal on use.
        Task { _ = try? await ClaudeAPIClient().ensureAPIKey() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(settingsStore)
                .environment(subscriptionManager)
                .preferredColorScheme(themePreference.colorScheme)   // manual Light/Dark override; .system = follow device
                .environment(\.locale, AppLanguage.current.locale)
                // Language switch → rebuild the whole tree so every string re-resolves live.
                .id(appLanguageRaw)
                // An expired/refunded subscription must lose Pro on return,
                // not at the next cold launch.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await subscriptionManager.updatePurchasedProducts() }
                    }
                }
        }
    }
}
