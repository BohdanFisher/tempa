import SwiftUI
import CoreData

struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var showWelcomeBack = false

    var body: some View {
        ZStack {
            if settings.onboardingCompleted {
                MainTabView()
            } else {
                OnboardingFlow()
            }
        }
        .fullScreenCover(isPresented: $showWelcomeBack) {
            WelcomeBackView {
                WelcomeBackView.markShown()
                showWelcomeBack = false
            }
        }
        .onAppear {
            if settings.onboardingCompleted && WelcomeBackView.shouldShow() {
                showWelcomeBack = true
            }
            WelcomeBackView.recordAppOpen()
        }
    }
}

#Preview {
    RootView()
        .environment(SettingsStore(context: PersistenceController.preview.container.viewContext))
        .environment(SubscriptionManager.shared)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
