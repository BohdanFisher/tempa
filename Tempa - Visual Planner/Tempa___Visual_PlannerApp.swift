import SwiftUI
import CoreData

@main
struct TempaApp: App {
    // Stored properties initialize in declaration order — this boots the debug
    // StoreKit test store BEFORE SubscriptionManager below asks for products.
    private let debugStoreKit: Void = DebugStoreKit.activate()

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
