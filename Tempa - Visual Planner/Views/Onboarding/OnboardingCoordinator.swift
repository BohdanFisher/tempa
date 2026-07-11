import SwiftUI

@Observable
final class OnboardingState {
    var currentStep = 0
    var selfIdPicks: Set<Int> = []
    var painPicks: Set<Int> = []
    var wakeTime = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: Date()) ?? Date()
    var energyDipTime: Date?
    var notificationsGranted = false
    var showPaywall = false

    let totalSteps = 9

    func next() {
        if currentStep < totalSteps - 1 { currentStep += 1 }
    }
    func previous() {
        if currentStep > 0 { currentStep -= 1 }
    }
}

struct OnboardingFlow: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var state = OnboardingState()

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Screen 1 is a full-bleed coral hero with its own white progress bar.
                if state.currentStep != 0 {
                    OnbProgressBar(step: state.currentStep, total: state.totalSteps)
                }

                screenForStep(state.currentStep)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .id(state.currentStep)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: state.currentStep)
            }
        }
        .fullScreenCover(isPresented: $state.showPaywall) {
            PaywallView(allowDismiss: false) {
                settings.completeOnboarding()
            }
        }
    }

    @ViewBuilder
    private func screenForStep(_ step: Int) -> some View {
        switch step {
        case 0: Onb1HookView(state: state)
        case 1: Onb2SelfIdView(state: state)
        case 2: Onb3PainView(state: state)
        case 3: Onb4DemoView(state: state)
        case 4: Onb5PersonalView(state: state)
        case 5: Onb6SocialView(state: state)
        case 6: Onb7ForgiveView(state: state)
        case 7: Onb8NotifsView(state: state)
        case 8: Onb9BuildingView(state: state, settings: settings)
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
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
}

// MARK: - Section Label

struct OnbLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.custom(T.fontHeader, size: 12).weight(.heavy))
            .tracking(2.2)
            .foregroundColor(T.primary)
    }
}
