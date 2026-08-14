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
    var wakeTime = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: Date()) ?? Date()
    var energyDipTime: Date?
    var notificationsGranted = false
    var showPaywall = false

    let totalSteps = 11

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

    /// Fired once the funnel is done (paywall completed).
    var onFinished: (() -> Void)? = nil

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Screen 1 is a full-bleed coral hero with its own white progress bar.
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
        .fullScreenCover(isPresented: $state.showPaywall) {
            PaywallView(allowDismiss: false) {
                saveDemoSteps()
                settings.completeOnboarding()
                onFinished?()
            }
        }
    }

    /// The demo's micro-steps become the user's first real tasks — but only
    /// now, at completion. Abandoned onboarding writes nothing.
    private func saveDemoSteps() {
        guard !state.demoSteps.isEmpty else { return }
        var start = Date()
        for step in state.demoSteps {
            let task = TaskBlock(context: viewContext)
            task.id = UUID()
            task.title = step.title
            task.iconName = step.icon
            task.category = "work"
            task.startTime = start
            task.durationMinutes = Int32(step.duration)
            task.createdAt = Date()
            start = start.addingTimeInterval(TimeInterval(step.duration) * 60)
        }
        try? viewContext.save()
        state.demoSteps = []
    }

    @ViewBuilder
    private func screenForStep(_ step: Int) -> some View {
        switch step {
        case 0: Onb1HookView(state: state)
        case 1: Onb2SelfIdView(state: state)
        case 2: Onb3PainView(state: state)
        case 3: OnbMicroYesView(state: state)
        case 4: Onb4DemoView(state: state)
        case 5: Onb5PersonalView(state: state)
        case 6: OnbPlanPreviewView(state: state)
        case 7: Onb6SocialView(state: state)
        case 8: Onb7ForgiveView(state: state)
        case 9: Onb8NotifsView(state: state)
        case 10: Onb9BuildingView(state: state, settings: settings)
        default: EmptyView()
        }
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
