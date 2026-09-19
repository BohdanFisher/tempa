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
    /// What the user said their day has on it, laid out by the AI — written
    /// to the feed only when onboarding completes, so an abandoned run
    /// leaves no orphan tasks. Empty when the screen was skipped.
    var dayPlan: [PlannedTask] = []
    var dayDump = ""
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

    let totalSteps = 20

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
        .onAppear {
            AnalyticsService.shared.track(.onboardingScreenView,
                                          properties: ["step": state.currentStep,
                                                       "name": Self.stepName(state.currentStep)])
        }
        .onChange(of: state.currentStep) { _, step in
            AnalyticsService.shared.track(.onboardingScreenView,
                                          properties: ["step": step, "name": Self.stepName(step)])
        }
        .fullScreenCover(isPresented: $state.showPaywall, onDismiss: {
            if finishAfterDismiss { onFinished?() }
        }) {
            PaywallView(allowDismiss: false) {
                AnalyticsService.shared.track(.onboardingCompleted)
                FirstDayStash.materialize(into: viewContext, settings: settings)
                settings.completeOnboarding()
                if onFinished != nil { finishAfterDismiss = true }
            }
        }
        .onChange(of: state.showPaywall) { _, shown in
            guard shown else { return }
            // The first day must survive a kill at the paywall — the relaunch
            // lands on the ROOT paywall, where this funnel's memory is gone.
            FirstDayStash.stash(FirstDayPlan(dump: state.dayDump, tasks: state.dayPlan, stashedAt: Date()))
            // Forced test runs (RootView passes onFinished: fresh dev install
            // or "-force-onboarding") must not persist the flag — the next
            // NORMAL launch would land on a hard paywall instead of the app.
            guard onFinished == nil else { return }
            hasCompletedOnboarding = true
        }
    }

    /// Funnel step names for analytics — index-aligned with screenForStep.
    private static let stepNames = [
        "welcome", "problem", "solution", "name", "quiz_self", "quiz_pain",
        "hours_lost", "math", "mirror", "micro_yes", "wake_time", "calendar_sync",
        "ai_demo", "building", "summary", "forgiveness", "social_proof",
        "notifications", "commitment", "trial_gift",
    ]
    private static func stepName(_ i: Int) -> String {
        stepNames.indices.contains(i) ? stepNames[i] : "step_\(i)"
    }

    /// Three acts (the funnel is a story): Introduction 0–8 builds the problem
    /// and lets the user tell us — and themselves — why they're here; Climax
    /// 9–14 has them DO the core thing, set their own rhythm, watch the app
    /// build on it and see the result; Conclusion 15–19 mirrors it all back
    /// and walks into the paywall.
    /// (Wake time and the calendar come BEFORE the day plan: the plan is laid
    /// out from the first and around the second — connect a calendar and the
    /// very next screen shows your real meetings with your tasks fitted
    /// between them. That is also why the calendar ask sits here and not by
    /// the notifications ask: permission is requested where it pays off on
    /// the next tap, and the two system prompts stay five screens apart.
    /// "ai_demo" is the analytics name of the plan screen — kept so the
    /// PostHog funnel keeps its history. "Building" sits right after the
    /// inputs it claims to build on, and the summary is the reveal.)
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
        case 10: Onb5PersonalView(state: state)
        case 11: OnbCalendarView(state: state)
        case 12: OnbDayPlanView(state: state)
        case 13: Onb9BuildingView(state: state, settings: settings)
        case 14: OnbSummaryView(state: state)
        case 15: Onb7ForgiveView(state: state)
        case 16: Onb6SocialView(state: state)
        case 17: Onb8NotifsView(state: state)
        // The active "yes" sits right before the offer, where it still counts.
        case 18: OnbCommitView(state: state)
        case 19: OnbTrialGiftView(state: state)
        default: EmptyView()
        }
    }
}

// MARK: - First day stash

/// The first day, parked in UserDefaults from the moment the funnel reaches
/// the paywall until a purchase completes — on EITHER paywall (the funnel's
/// cover, or the root one after a kill-and-relaunch). The feed itself is
/// only written on purchase, so a run that never pays leaves no tasks.
enum FirstDayStash {
    private static let key = "pendingFirstDay"

    static func stash(_ plan: FirstDayPlan) {
        guard let data = try? JSONEncoder().encode(plan) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Writes the first day as the user's real tasks. Today or tomorrow is
    /// decided NOW, not when the plan was typed — the stash may be days old
    /// (killed at the paywall, back later), and a plan for a day that's gone
    /// helps no one.
    static func materialize(into context: NSManagedObjectContext, settings: SettingsStore) {
        // One-shot: no stash means the first day was already written (a
        // lapsed subscriber buying again on the root paywall must not get a
        // second seeded week).
        guard let data = UserDefaults.standard.data(forKey: key),
              let plan = try? JSONDecoder().decode(FirstDayPlan.self, from: data) else { return }
        UserDefaults.standard.removeObject(forKey: key)
        // These are written FOR the user by onboarding — they must not count
        // as the first task they created (no rating prompt on a plan they
        // haven't even seen yet).
        ReviewPrompt.isWritingDemoPlan = true
        defer { ReviewPrompt.isWritingDemoPlan = false }
        // The calendar lands first, so the user's own tasks are laid out
        // around their real meetings — the same day the funnel previewed.
        CalendarSync.shared.sync(into: context)
        let now = Date()
        let day = DayBuilder.targetDay(now: now, wake: settings.wakeTime)
        let horizon = Calendar.current.date(byAdding: .day, value: 8, to: day) ?? day
        let drafts = DayBuilder.build(plan: plan, wake: settings.wakeTime, dip: settings.energyDipTime,
                                      now: now, around: SlotFinder.busy(from: now, to: horizon, context: context))
        DayBuilder.write(drafts, into: context)
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
