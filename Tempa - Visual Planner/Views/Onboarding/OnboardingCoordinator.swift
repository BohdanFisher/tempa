import SwiftUI
import CoreData

@Observable
final class OnboardingState {
    #if DEBUG
    // Dev shortcut: launch with "-onb-step N" to jump straight to a screen.
    var currentStep = UserDefaults.standard.integer(forKey: "onb-step")
    #else
    var currentStep = 0
    #endif
    /// Micro-steps generated in the AI demo — written to the feed only when
    /// onboarding completes, so an abandoned run leaves no orphan tasks.
    var demoSteps: [TaskBreakdown.Step] = []
    var selfIdPicks: Set<Int> = []
    var painPicks: Set<Int> = []
    /// First name for personalization — mirrors, summary, and later the app
    /// itself. Empty when the user skipped the ask.
    var userName = ""
    /// Self-reported hours lost per heavy day — feeds the "do the math" screen.
    var hoursLost: Double = 3
    var wakeTime = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: Date()) ?? Date()
    var energyDipTime: Date?
    var notificationsGranted = false
    var showPaywall = false

    let totalSteps = 21

    func next() {
        if currentStep < totalSteps - 1 { currentStep += 1 }
    }
    func previous() {
        if currentStep > 0 { currentStep -= 1 }
    }
}

struct OnboardingFlow: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.managedObjectContext) private var viewContext
    @State private var state = OnboardingState()
    /// Set the moment the funnel reaches the paywall — from then on RootView
    /// routes a relaunch straight to the paywall instead of replaying all the
    /// funnel screens. UserDefaults on purpose: a reinstall clears it.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Fired once the funnel is done (paywall completed).
    var onFinished: (() -> Void)? = nil

    /// Set when the forced-funnel paywall completes a purchase. The hand-off
    /// to RootView (onFinished) must wait until the cover has FULLY dismissed:
    /// firing it while the cover is still presented swaps the root branch out
    /// from under a live presentation, which can leave the paywall stuck on
    /// screen after a successful purchase.
    @State private var finishAfterDismiss = false

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // The welcome door stays chrome-free — the bar appears from screen 2.
                if state.currentStep != 0 {
                    OnbProgressBar(step: state.currentStep, total: state.totalSteps)
                }

                // Springy push — the next step glides in from the right. Not gated
                // behind Reduce Motion: it's core feedback, and gentle by design.
                screenForStep(state.currentStep)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .id(state.currentStep)
                    .animation(.spring(response: 0.5, dampingFraction: 0.86), value: state.currentStep)
            }
        }
        .fullScreenCover(isPresented: $state.showPaywall, onDismiss: {
            if finishAfterDismiss { onFinished?() }
        }) {
            PaywallView(allowDismiss: false) {
                DemoPlanStash.materialize(into: viewContext)
                settings.completeOnboarding()
                if onFinished != nil { finishAfterDismiss = true }
            }
        }
        .onChange(of: state.showPaywall) { _, shown in
            guard shown else { return }
            // The demo plan must survive a kill at the paywall — the relaunch
            // lands on the ROOT paywall, where this funnel's memory is gone.
            DemoPlanStash.stash(state.demoSteps)
            // Forced test runs (RootView passes onFinished: fresh dev install
            // or "-force-onboarding") must not persist the flag — the next
            // NORMAL launch would land on a hard paywall instead of the app.
            guard onFinished == nil else { return }
            hasCompletedOnboarding = true
        }
    }

    /// Three acts (the funnel is a story): Introduction 0–8 builds the problem
    /// and lets the user tell us — and themselves — why they're here; Climax
    /// 9–13 has them DO the core thing and feel the win; Conclusion 14–19
    /// mirrors it all back and walks into the paywall.
    @ViewBuilder
    private func screenForStep(_ step: Int) -> some View {
        switch step {
        case 0: OnbWelcomeView(state: state)
        case 1: OnbProblemView(state: state)
        case 2: OnbSolutionView(state: state)
        case 3: OnbNameView(state: state)
        case 4: Onb2SelfIdView(state: state)
        case 5: Onb3PainView(state: state)
        case 6: OnbHoursView(state: state)
        case 7: OnbBombshellView(state: state)
        case 8: OnbMirrorView(state: state)
        case 9: OnbMicroYesView(state: state)
        case 10: Onb4DemoView(state: state)
        case 11: OnbFirstWinView(state: state)
        case 12: Onb5PersonalView(state: state)
        case 13: OnbPlanPreviewView(state: state)
        case 14: Onb7ForgiveView(state: state)
        case 15: OnbCommitView(state: state)
        case 16: OnbSummaryView(state: state)
        case 17: Onb6SocialView(state: state)
        case 18: Onb8NotifsView(state: state)
        case 19: Onb9BuildingView(state: state, settings: settings)
        case 20: OnbTrialGiftView(state: state)
        default: EmptyView()
        }
    }
}

// MARK: - Demo plan stash

/// The onboarding demo's micro-steps, parked in UserDefaults from the moment
/// the funnel reaches the paywall until a purchase completes — on EITHER
/// paywall (the funnel's cover, or the root one after a kill-and-relaunch).
/// The feed itself is only written on purchase, so a run that never pays
/// still leaves no orphan tasks.
enum DemoPlanStash {
    private static let key = "pendingDemoSteps"

    static func stash(_ steps: [TaskBreakdown.Step]) {
        guard !steps.isEmpty, let data = try? JSONEncoder().encode(steps) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Writes the stashed steps as the user's first real tasks, starting NOW —
    /// the stash may be days old, and a plan scheduled in the past helps no one.
    static func materialize(into context: NSManagedObjectContext) {
        guard let data = UserDefaults.standard.data(forKey: key),
              let steps = try? JSONDecoder().decode([TaskBreakdown.Step].self, from: data),
              !steps.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: key)
        // These are written FOR the user by onboarding — they must not count
        // as the first task they created (no rating prompt on a plan they
        // haven't even seen yet).
        ReviewPrompt.isWritingDemoPlan = true
        defer { ReviewPrompt.isWritingDemoPlan = false }
        var start = Date()
        for step in steps {
            let task = TaskBlock(context: context)
            task.id = UUID()
            task.title = step.title
            task.iconName = step.icon
            task.category = "work"
            task.startTime = start
            task.durationMinutes = Int32(step.duration)
            task.createdAt = Date()
            start = start.addingTimeInterval(TimeInterval(step.duration) * 60)
        }
        try? context.save()
    }
}

// MARK: - Progress Bar

struct OnbProgressBar: View {
    let step: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i <= step ? T.primary : Color(lightHex: "#EAE5DA", darkHex: "#2E2722"))
                    .frame(height: 4)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: step)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
}

// MARK: - Section Label

struct OnbLabel: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .font(.custom(T.fontHeader, size: 12).weight(.heavy))
            .tracking(2.2)
            .foregroundColor(T.primary)
    }
}
