import SwiftUI
import CoreData

struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var showWelcomeBack = false
    @Environment(\.scenePhase) private var scenePhase
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
        // A daily user who never cold-launches must not be greeted with
        // "you took a break" — record every trip to the background, and check
        // the gap again on every return (long breaks often end in a warm
        // resume, where onAppear never refires).
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if settings.onboardingCompleted && WelcomeBackView.shouldShow() {
                    showWelcomeBack = true
                }
                WelcomeBackView.recordAppOpen()
            case .background:
                WelcomeBackView.recordAppOpen()
            default:
                break
            }
        }
    }
}

#Preview {
    RootView()
        .environment(SettingsStore(context: PersistenceController.preview.container.viewContext))
        .environment(SubscriptionManager.shared)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
