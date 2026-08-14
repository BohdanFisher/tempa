import SwiftUI
import CoreData

struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var showWelcomeBack = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var planAfterWelcome = false

    /// Dev shortcut: launch with "-force-onboarding YES" to see onboarding even
    /// though iCloud has already restored a completed profile. On a reinstall
    /// CloudKit brings onboardingCompleted back within seconds — correct for
    /// real users, maddening when you're trying to TEST onboarding.
    private var forceOnboarding: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "force-onboarding")
        #else
        false
        #endif
    }

    var body: some View {
        ZStack {
            if settings.onboardingCompleted && !forceOnboarding {
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
