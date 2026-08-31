import SwiftUI
import CoreData

struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SubscriptionManager.self) private var subs
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showWelcomeBack = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var planAfterWelcome = false
    /// A forced test run of the funnel ends when the funnel ends — otherwise
    /// the flag would trap the tester on the last screen forever.
    @State private var forcedFunnelDone = false
    /// Deliberately UserDefaults, not the CloudKit-synced settings flag: it
    /// survives relaunches but dies with the app container, so a reinstall
    /// gets the fresh funnel while a mid-paywall relaunch does not replay it.
    /// Read ONCE per launch (@State, not @AppStorage) on purpose — the funnel
    /// sets this flag the moment it presents its own paywall, and a reactive
    /// read here would instantly tear the live funnel (and its unsaved demo
    /// plan) down to swap in the root paywall. Mid-session, StoreKit alone
    /// moves the routing; the flag only decides where the NEXT launch lands.
    @State private var hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

    /// The owner's phone (OwnerMode) keeps showing the funnel until it has
    /// been COMPLETED once on this install (purchase at the funnel paywall) —
    /// across any number of exits and relaunches, including the process kill
    /// an iOS language change causes. Stale test/sandbox entitlements never
    /// skip it. Completing the funnel ends the cycle; deleting the app (the
    /// marker dies with the container) or "-wipe-data YES" restarts it.
    /// Owner-only: everyone else routes by subscription from the first launch.
    @State private var funnelCompletedOnThisInstall =
        UserDefaults.standard.bool(forKey: "funnelCompletedOnce")

    /// Dev shortcut: launch with "-force-onboarding YES" to see onboarding even
    /// though iCloud has already restored a completed profile. On a reinstall
    /// CloudKit brings onboardingCompleted back within seconds — correct for
    /// real users, maddening when you're trying to TEST onboarding.
    private var forceOnboarding: Bool {
        guard OwnerMode.isActive else { return false }
        return UserDefaults.standard.bool(forKey: "force-onboarding")
            || !funnelCompletedOnThisInstall
    }

    var body: some View {
        ZStack {
            // Two sources of truth with different lifetimes, on purpose:
            //   StoreKit (Apple ID)  — isPro/hasEverSubscribed survive reinstalls
            //   UserDefaults         — hasCompletedOnboarding survives relaunches only
            // Routing: subscription active → straight in; funnel finished (or
            // lapsed subscriber) but unpaid → hard paywall; otherwise onboarding.
            // Onboarding is gated on the flag AND the subscription, so a
            // subscriber reinstalling online skips the funnel — StoreKit pulls
            // the entitlement from their Apple ID in the first local pass.
            // (Offline reinstall can't see the Apple ID yet and starts the
            // funnel; Transaction.updates self-heals into Main once synced.)
            if forceOnboarding && !forcedFunnelDone {
                OnboardingFlow(onFinished: {
                    forcedFunnelDone = true
                    // Funnel finished for real — stop forcing it on this
                    // install; from here on routing goes by subscription.
                    UserDefaults.standard.set(true, forKey: "funnelCompletedOnce")
                    funnelCompletedOnThisInstall = true
                })
            } else if !subs.entitlementsChecked {
                T.bg.ignoresSafeArea()   // sub-second, offline-safe
            } else if subs.isPro {
                MainTabView()
            } else if hasCompletedOnboarding || subs.hasEverSubscribed {
                PaywallView(allowDismiss: false) {
                    // Killed at the funnel's paywall, bought here after the
                    // relaunch — their demo plan still becomes their first day.
                    DemoPlanStash.materialize(into: viewContext)
                    // That cohort finishes onboarding HERE, not in the funnel —
                    // without this the ad platforms see their trial/purchase
                    // with no Registration before it. A lapsed subscriber
                    // re-subscribing isn't finishing onboarding, so skip them.
                    if !subs.hasEverSubscribed {
                        AnalyticsService.shared.track(.onboardingCompleted)
                    }
                    settings.completeOnboarding()
                }
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
