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
        let context = PersistenceController.shared.container.viewContext
        _settingsStore = State(initialValue: SettingsStore(context: context))

        TaskNotifications.startObserving(context)
        AppLanguage.current.apply()   // keep the AppleLanguages override in sync

        #if DEBUG
        ClaudeAPIClient().setupDevKey()
        #endif
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
