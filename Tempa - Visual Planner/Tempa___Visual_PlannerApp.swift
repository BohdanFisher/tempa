import SwiftUI
import CoreData

@main
struct TempaApp: App {
    let persistenceController = PersistenceController.shared
    let subscriptionManager = SubscriptionManager.shared

    @State private var settingsStore: SettingsStore
    @AppStorage("themePreference") private var themePreference: ThemePreference = .system

    init() {
        let context = PersistenceController.shared.container.viewContext
        _settingsStore = State(initialValue: SettingsStore(context: context))

        TaskNotifications.startObserving(context)

        #if DEBUG
        ClaudeAPIClient().setupDevKey()
        // Boot the debug StoreKit test store OFF the main thread — SKTestSession
        // init can block on a storekitd handshake, and blocking here would hold
        // the first frame hostage (white screen). SubscriptionManager retries,
        // and the paywall retries again on appear, so late activation is fine.
        Task.detached(priority: .userInitiated) {
            DebugStoreKit.activate()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(settingsStore)
                .environment(subscriptionManager)
                .preferredColorScheme(themePreference.colorScheme)   // manual Light/Dark override; .system = follow device
        }
    }
}
