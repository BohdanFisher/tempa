import SwiftUI
import CoreData

struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var showWelcomeBack = false
    @State private var planAfterWelcome = false

    var body: some View {
        ZStack {
            if settings.onboardingCompleted {
                MainTabView()
            } else {
                OnboardingFlow()
            }
        }
        .fullScreenCover(isPresented: $showWelcomeBack, onDismiss: {
            // Fire after the cover fully dismisses, so the add-task sheet
            // doesn't fight the closing animation for the presentation slot.
            if planAfterWelcome {
                planAfterWelcome = false
                AppRouter.shared.selectedTab = .today
                AppRouter.shared.addTaskRequest = UUID()
            }
        }) {
            WelcomeBackView(
                onPlan: {
                    WelcomeBackView.markShown()
                    planAfterWelcome = true
                    showWelcomeBack = false
                },
                onDismiss: {
                    WelcomeBackView.markShown()
                    showWelcomeBack = false
                }
            )
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
