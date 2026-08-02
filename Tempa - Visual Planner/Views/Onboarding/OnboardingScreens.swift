import SwiftUI
import UserNotifications
import CoreData

// MARK: - Screen 1: Hook

struct Onb1HookView: View {
    let state: OnboardingState

    // Bright coral in light mode; a deeper, calmer coral in dark mode (the bright
    // one glares on a dark screen). White text/buttons read well on both.
    private let coral = Color(lightHex: "#FF7A59", darkHex: "#B5503A")

    var body: some View {
        ZStack {
            coral.ignoresSafeArea()

            VStack(spacing: 0) {
                // Own progress bar — white on coral.
                HStack(spacing: 4) {
                    ForEach(0..<state.totalSteps, id: \.self) { i in
                        Capsule()
                            .fill(Color.white.opacity(i == 0 ? 1 : 0.28))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 0) {
                    Text("TEMPA")
                        .font(.custom("Nunito-ExtraBold", size: 13).weight(.heavy))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.72))
                        .padding(.bottom, 16)
                        .staggerIn(0)

                    (
                        Text("The ADHD-friendly planner that moves at your ")
                            .font(.custom("Nunito-ExtraBold", size: 38).weight(.heavy))
                            .foregroundColor(.white)
                        + Text("tempo.")
                            .font(.system(size: 38, weight: .semibold, design: .serif))
                            .italic()
                            .foregroundColor(.white.opacity(0.9))
                    )
                    .tracking(-0.6)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .staggerIn(1)

                    Text("Voice-first planning with AI scheduling and a built-in focus timer — one task at a time.")
                        .font(.custom("Inter-Medium", size: 16).weight(.medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineSpacing(4)
                        .padding(.top, 16)
                        .fixedSize(horizontal: false, vertical: true)
                        .staggerIn(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 26)

                TempaWaveform(color: .white, maxHeight: 118)
                    .frame(height: 150)
                    .padding(.top, 26)
                    .padding(.horizontal, 26)
                    .staggerIn(3)

                Spacer(minLength: 12)

                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    state.next()
                } label: {
                    HStack(spacing: 10) {
                        Text("Find my tempo")
                            .font(.custom("Nunito-ExtraBold", size: 17).weight(.heavy))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(coral)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 19)
                    .background(Capsule().fill(.white))
                    .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
                }
                .buttonStyle(SpringPressStyle())
                .padding(.horizontal, 22)
                .staggerIn(4)

                Text("Takes 60 seconds · free to try")
                    .font(.custom("Inter-Medium", size: 13).weight(.medium))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                    .staggerIn(5)
            }
        }
    }

}

// MARK: - Screen 2: Self-Identification

struct Onb2SelfIdView: View {
    let state: OnboardingState

    private let rows: [(LocalizedStringKey, String, String)] = [
        ("I have ADHD / I'm neurodivergent", "brain.head.profile", "health"),
        ("I get overwhelmed by my to-do list", "tray.full", "work"),
        ("I procrastinate on important things", "hourglass", "personal"),
        ("I lose track of time", "clock", "routine"),
        ("I just want a calmer day", "leaf", "rest"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                OnbLabel(text: "About you · 1 of 3")

                Text("What brings you here?")
                    .font(.custom("Nunito-ExtraBold", size: 28).weight(.heavy))
                    .tracking(-0.56)
                    .foregroundColor(T.text)
                    .lineSpacing(-2)
                    .padding(.top, 10)

                Text("Pick all that feel true. We'll tune Tempa to you.")
                    .font(.custom("Inter-Medium", size: 14).weight(.medium))
                    .foregroundColor(T.textSec)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 32)

            VStack(spacing: 10) {
                ForEach(rows.indices, id: \.self) { i in
                    QuizRow(label: rows[i].0, icon: rows[i].1, cat: rows[i].2, picked: state.selfIdPicks.contains(i)) {
                        if state.selfIdPicks.contains(i) {
                            state.selfIdPicks.remove(i)
                        } else {
                            state.selfIdPicks.insert(i)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)

            Spacer()

            TempaButton(label: "Continue", variant: .primary, size: .lg, fullWidth: true, showArrow: true) {
                state.next()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 50)
        }
    }
}

// MARK: - Screen 3: Pain Amplification

struct Onb3PainView: View {
    let state: OnboardingState

    private let rows: [(LocalizedStringKey, String, String)] = [
        ("Starting tasks", "play.circle", "work"),
        ("Time blindness — losing hours", "hourglass", "routine"),
        ("Remembering routines", "alarm", "personal"),
        ("Too many apps that didn't stick", "square.stack.3d.up.slash", "social"),
        ("Feeling guilty when I fall behind", "heart", "health"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                OnbLabel(text: "About you · 2 of 3")

                Text("What's hardest for you?")
                    .font(.custom("Nunito-ExtraBold", size: 28).weight(.heavy))
                    .tracking(-0.56)
                    .foregroundColor(T.text)
                    .lineSpacing(-2)
                    .padding(.top, 10)

                Text("So we know what to fix first.")
                    .font(.custom("Inter-Medium", size: 14).weight(.medium))
                    .foregroundColor(T.textSec)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 32)

            VStack(spacing: 10) {
                ForEach(rows.indices, id: \.self) { i in
                    QuizRow(label: rows[i].0, icon: rows[i].1, cat: rows[i].2, picked: state.painPicks.contains(i)) {
                        if state.painPicks.contains(i) {
                            state.painPicks.remove(i)
                        } else {
                            state.painPicks.insert(i)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)

            Spacer()

            TempaButton(label: "Continue", variant: .primary, size: .lg, fullWidth: true, showArrow: true) {
                state.next()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 50)
        }
    }
}

// MARK: - QuizRow

struct QuizRow: View {
    let label: LocalizedStringKey
    var icon: String? = nil
    var cat: String = "personal"
    let picked: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            onTap()
        } label: {
            HStack(spacing: 12) {
                if let icon {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Cat.named(cat).bg)
                            .frame(width: 32, height: 32)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Cat.named(cat).ink)
                    }
                }

                Text(label)
                    .font(.custom("Inter-Medium", size: 16))
                    .foregroundColor(T.text)

                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(picked ? T.primary : T.surface)
                        .frame(width: 26, height: 26)
                    if !picked {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(T.textTer, lineWidth: 1.5)
                            .frame(width: 26, height: 26)
                    }
                    if picked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.6), value: picked)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(picked ? Cat.personal.bg : T.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(picked ? T.primary : .clear, lineWidth: 1.5)
            )
            .tempaShadowSm()
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: picked)
        }
        .buttonStyle(SpringPressStyle())
    }
}

// MARK: - Screen: Micro-commitment (one small "yes" right before the demo)

struct OnbMicroYesView: View {
    let state: OnboardingState

    private let options: [LocalizedStringKey] = ["Yes, completely", "Probably", "I want to find out"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnbLabel(text: "Quick question")
                .padding(.top, 32)

            Text("If you finished one important thing a day — would your week feel different?")
                .font(.custom("Nunito-ExtraBold", size: 28).weight(.heavy))
                .tracking(-0.56)
                .foregroundColor(T.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            VStack(spacing: 10) {
                ForEach(Array(options.enumerated()), id: \.offset) { i, label in
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        state.next()
                    } label: {
                        HStack {
                            Text(label)
                                .font(.custom("Nunito-ExtraBold", size: 16).weight(.bold))
                                .foregroundColor(T.text)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(T.primary)
                        }
                        .padding(18)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(T.surface))
                        .tempaShadowSm()
                    }
                    .buttonStyle(SpringPressStyle())
                    .staggerIn(i)
                }
            }
            .padding(.top, 26)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
    }
}

// MARK: - Screen 4: AI Demo

struct Onb4DemoView: View {
    let state: OnboardingState
    @Environment(\.managedObjectContext) private var viewContext

    @State private var taskText = ""
    @State private var steps: [TaskBreakdown.Step] = []
    @State private var isLoading = false
    @State private var showResult = false
    @State private var didSave = false
    @FocusState private var focused: Bool

    private let apiClient = ClaudeAPIClient()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OnbLabel(text: "The aha moment")
                    .padding(.top, 24)

                Text("Try it. Type something you've been avoiding.")
                    .font(.custom("Nunito-ExtraBold", size: 28).weight(.heavy))
                    .tracking(-0.56)
                    .foregroundColor(T.text)
                    .lineSpacing(-2)
                    .padding(.top, 10)

                if showResult {
                    resultCard
                } else {
                    inputCard

                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        focused = false
                        state.next()
                    } label: {
                        Text("Skip")
                            .font(.custom("Inter-Medium", size: 14))
                            .foregroundColor(T.textSec)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 18)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 50)
        }
        .onAppear { focused = true }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What's on your mind?")
                    .font(.custom("Inter-Medium", size: 13).weight(.medium))
                    .foregroundColor(T.textSec)

                TextField("e.g. File my taxes", text: $taskText)
                    .font(.custom("Nunito-ExtraBold", size: 19).weight(.bold))
                    .foregroundColor(T.text)
                    .focused($focused)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(T.surface)
            )
            .tempaShadowSm()
            .padding(.top, 22)

            if isLoading {
                HStack(spacing: 12) {
                    Spacer()
                    TempaWaveform(color: T.primary, bars: 9, maxHeight: 26, barWidth: 4, spacing: 4)
                        .frame(width: 60, height: 30)
                    Text("Breaking it down...")
                        .font(.custom("Nunito-ExtraBold", size: 14).weight(.semibold))
                        .foregroundColor(T.textSec)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else {
                TempaButton(label: "Break it down", variant: .primary, size: .lg, fullWidth: true) {
                    Task { await doBreakdown() }
                }
                .padding(.top, 16)
                .opacity(taskText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                .disabled(taskText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "You typed" card
            VStack(alignment: .leading, spacing: 6) {
                Text("YOU TYPED")
                    .font(.custom("Nunito-ExtraBold", size: 11).weight(.bold))
                    .tracking(1.1)
                    .foregroundColor(T.textSec)

                Text(taskText)
                    .font(.custom("Nunito-ExtraBold", size: 19).weight(.bold))
                    .foregroundColor(T.text)
                    .tracking(-0.2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(T.surface)
            )
            .tempaShadowSm()
            .padding(.top, 22)

            // "Tempa broke it down" label
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(lightHex: "#FFE9E1", darkHex: "#2C1F18"), Color(lightHex: "#D6F0E7", darkHex: "#16302A")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "sparkle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(T.primary)
                    )

                Text("Tempa broke it down")
                    .font(.custom("Nunito-ExtraBold", size: 14).weight(.heavy))
                    .foregroundColor(T.text)
            }
            .padding(.top, 22)
            .padding(.bottom, 12)

            // Steps
            VStack(spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    MicroStepCard(step: step, index: i + 1) { deleteStep(at: i) }
                }
            }

            // "Not so scary" banner
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Cat.health.ink)
                Text("See? Not so scary when it's this small.")
                    .font(.custom("Nunito-ExtraBold", size: 15).weight(.bold))
                    .foregroundColor(T.text)
                    .lineSpacing(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Cat.health.bg)
            )
            .padding(.top, 22)

            TempaButton(label: "That helps. Continue", variant: .primary, size: .lg, fullWidth: true, showArrow: true) {
                saveStepsToFeed()
                state.next()
            }
            .padding(.top, 16)
        }
    }

    private func doBreakdown() async {
        isLoading = true
        focused = false
        do {
            let result = try await apiClient.breakDown(task: taskText)
            steps = result.steps
        } catch {
            steps = FallbackBreakdown.generate(for: taskText).steps
        }
        isLoading = false
        withAnimation(.easeInOut(duration: 0.3)) {
            showResult = true
        }
    }

    private func deleteStep(at index: Int) {
        guard steps.indices.contains(index) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            _ = steps.remove(at: index)
        }
    }

    /// Persist the steps the user generated during onboarding as real tasks,
    /// scheduled back-to-back from now, so they appear in the task feed.
    private func saveStepsToFeed() {
        guard !steps.isEmpty, !didSave else { return }
        didSave = true
        var start = Date()
        for step in steps {
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
    }
}

// MARK: - Screen 5: Personalization

struct Onb5PersonalView: View {
    @Bindable var state: OnboardingState

    @State private var wakeHour: Double = 6.75

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                OnbLabel(text: "Set your day · 3 of 3")

                Text("When does your day start?")
                    .font(.custom("Nunito-ExtraBold", size: 28).weight(.heavy))
                    .tracking(-0.56)
                    .foregroundColor(T.text)
                    .lineSpacing(-2)
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 32)

            // Clock card
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formattedTime)
                        .font(.custom("Nunito-ExtraBold", size: 44).weight(.heavy))
                        .tracking(-0.88)
                        .foregroundColor(T.text)
                        .monospacedDigit()
                    if !formattedPeriod.isEmpty {
                        Text(formattedPeriod)
                            .font(.custom("Nunito-ExtraBold", size: 22).weight(.heavy))
                            .foregroundColor(T.textSec)
                    }
                }
                .frame(maxWidth: .infinity)

                // The sun rides the arc as the wake time moves — you SEE the
                // morning you're choosing.
                GeometryReader { geo in
                    let w = geo.size.width
                    let t = CGFloat((wakeHour - 5) / 7)
                    let p0 = CGPoint(x: 12, y: 62), p1 = CGPoint(x: w - 12, y: 62)
                    let c = CGPoint(x: w / 2, y: -26)
                    let sx = (1-t)*(1-t)*p0.x + 2*(1-t)*t*c.x + t*t*p1.x
                    let sy = (1-t)*(1-t)*p0.y + 2*(1-t)*t*c.y + t*t*p1.y
                    ZStack {
                        SunArcShape()
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 5]))
                            .foregroundColor(Color(lightHex: "#EAE5DA", darkHex: "#2E2722"))
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Cat.routine.ink)
                            .position(x: sx, y: sy)
                    }
                }
                .frame(height: 68)
                .padding(.top, 10)

                // Custom slider
                GeometryReader { geo in
                    let trackWidth = geo.size.width
                    let pct = (wakeHour - 5) / 7

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(lightHex: "#EAE5DA", darkHex: "#2E2722"))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(T.primary)
                            .frame(width: trackWidth * pct, height: 6)

                        Circle()
                            .fill(T.surface)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .stroke(T.primary, lineWidth: 3)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                            .offset(x: trackWidth * pct - 14)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let newPct = min(max(value.location.x / trackWidth, 0), 1)
                                        let raw = 5 + newPct * 7
                                        let snapped = (raw * 4).rounded() / 4
                                        if snapped != wakeHour {
                                            #if os(iOS)
                                            UISelectionFeedbackGenerator().selectionChanged()
                                            #endif
                                        }
                                        wakeHour = snapped
                                    }
                                    .onEnded { _ in syncWakeTime() }
                            )
                    }
                }
                .frame(height: 28)
                .padding(.top, 18)

                HStack {
                    Text("5:00")
                    Spacer()
                    Text("9:00")
                    Spacer()
                    Text("12:00")
                }
                .font(.custom("Inter-Medium", size: 11).weight(.semibold))
                .foregroundColor(T.textSec)
                .padding(.top, 8)
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(T.surface)
            )
            .tempaShadowSm()
            .padding(.horizontal, 22)
            .padding(.top, 24)

            // Energy dip card
            energyDipCard
                .padding(.horizontal, 22)
                .padding(.top, 16)

            Spacer()

            TempaButton(label: "Looks right", variant: .primary, size: .lg, fullWidth: true, showArrow: true) {
                syncWakeTime()
                state.next()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 50)
        }
        .onAppear {
            let cal = Calendar.current
            let h = cal.component(.hour, from: state.wakeTime)
            let m = cal.component(.minute, from: state.wakeTime)
            wakeHour = Double(h) + Double(m) / 60.0
        }
    }

    private var energyDipCard: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Cat.personal.bg)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "flame.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Cat.personal.ink)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("When do you run out of steam?")
                    .font(.custom("Nunito-ExtraBold", size: 15).weight(.bold))
                    .foregroundColor(T.text)
                Text("We'll keep that block light.")
                    .font(.custom("Inter-Medium", size: 12).weight(.medium))
                    .foregroundColor(T.textSec)
            }

            Spacer()

            Menu {
                ForEach([13, 14, 15, 16, 17], id: \.self) { hour in
                    Button {
                        state.energyDipTime = Calendar.current.date(
                            bySettingHour: hour, minute: 0, second: 0, of: Date()
                        )
                    } label: {
                        Text(formatHour(hour))
                    }
                }
                Button("None") { state.energyDipTime = nil }
            } label: {
                HStack(spacing: 4) {
                    Text(energyDipLabel)
                        .font(.custom("Nunito-ExtraBold", size: 14).weight(.heavy))
                        .foregroundColor(T.text)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(T.textSec)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(T.bgWarm)
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(T.surface)
        )
        .tempaShadowSm()
    }

    /// AM/PM only where the user's region actually uses it (US/Canada);
    /// everywhere else this is a clean 24-hour clock.
    private var uses12h: Bool {
        switch Locale.current.hourCycle {
        case .oneToTwelve, .zeroToEleven: return true
        default: return false
        }
    }

    private var formattedTime: String {
        let h = Int(wakeHour)
        let m = Int((wakeHour - Double(h)) * 60)
        if uses12h {
            let displayH = h > 12 ? h - 12 : (h == 0 ? 12 : h)
            return String(format: "%d:%02d", displayH, m)
        }
        return String(format: "%02d:%02d", h, m)
    }

    private var formattedPeriod: String {
        uses12h ? (wakeHour >= 12 ? "PM" : "AM") : ""
    }

    private var energyDipLabel: String {
        guard let dip = state.energyDipTime else { return formatHour(15) }
        let h = Calendar.current.component(.hour, from: dip)
        return formatHour(h)
    }

    private func formatHour(_ h: Int) -> String {
        if uses12h {
            let display = h > 12 ? h - 12 : h
            return "\(display) \(h >= 12 ? "PM" : "AM")"
        }
        return String(format: "%02d:00", h)
    }

    private func syncWakeTime() {
        let h = Int(wakeHour)
        let m = Int((wakeHour - Double(h)) * 60)
        if let date = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) {
            state.wakeTime = date
        }
    }
}

// MARK: - Screen: Your day, visualised (value preview)

struct OnbPlanPreviewView: View {
    let state: OnboardingState

    private var wakePlus30: Date { state.wakeTime.addingTimeInterval(30 * 60) }
    private var midMorning: Date { state.wakeTime.addingTimeInterval(3 * 3600) }
    private var evening: Date {
        Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: state.wakeTime) ?? state.wakeTime
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnbLabel(text: "Your rhythm")
                .padding(.top, 32)

            Text("Here's a day that works with your brain")
                .font(.custom("Nunito-ExtraBold", size: 28).weight(.heavy))
                .tracking(-0.56)
                .foregroundColor(T.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            Text("Starts at your pace — \(state.wakeTime.formatted(date: .omitted, time: .shortened)). One small thing at a time.")
                .font(.custom("Inter-Medium", size: 15).weight(.medium))
                .foregroundColor(T.textSec)
                .lineSpacing(4)
                .padding(.top, 12)

            VStack(spacing: 0) {
                previewRow(time: wakePlus30, title: "One small win to start", icon: "sparkles", category: "personal", index: 0, isFirst: true)
                previewRow(time: midMorning, title: "One deep focus block", icon: "laptopcomputer", category: "work", index: 1)
                previewRow(time: evening, title: "Wind down, guilt-free", icon: "bed.double", category: "rest", index: 2, isLast: true)
            }
            .padding(.top, 24)

            Spacer()

            TempaButton(label: "Continue", variant: .primary, size: .lg, fullWidth: true, showArrow: true) {
                state.next()
            }
            .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
    }

    private func previewRow(time: Date, title: LocalizedStringKey, icon: String, category: String, index: Int,
                            isFirst: Bool = false, isLast: Bool = false) -> some View {
        let cc = Cat.named(category)
        return HStack(spacing: 10) {
            Text(time.formatted(date: .omitted, time: .shortened))
                .font(.custom("Nunito-ExtraBold", size: 12).weight(.bold))
                .foregroundColor(T.textSec)
                .frame(width: 50, alignment: .leading)

            // Time rail — same visual language as the real timeline.
            VStack(spacing: 0) {
                Rectangle().fill(T.bgWarm).frame(width: 2)
                    .opacity(isFirst ? 0 : 1)
                if isFirst {
                    PulseDot(size: 8, color: cc.solid, rings: 2, speed: 3)
                        .frame(width: 12, height: 12)
                } else {
                    Circle().fill(cc.solid).frame(width: 8, height: 8)
                }
                Rectangle().fill(T.bgWarm).frame(width: 2)
                    .opacity(isLast ? 0 : 1)
            }
            .frame(width: 14)

            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(cc.bg)
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(cc.ink)
                }
                Text(title)
                    .font(.custom("Nunito-ExtraBold", size: 15).weight(.bold))
                    .foregroundColor(T.text)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.surface))
            .tempaShadowSm()
            .padding(.vertical, 5)
        }
        .staggerIn(index)
    }
}

// MARK: - Screen 6: Social Proof

struct Onb6SocialView: View {
    let state: OnboardingState

    private let testimonials = [
        (quote: String(localized: "For the first time, I finish things. I just see the tiny next step and go.", bundle: .appLanguage), name: "Maya, 32"),
        (quote: String(localized: "No streaks to lose was the unlock for me. I'm three months in.", bundle: .appLanguage), name: "Jordan, 27"),
        (quote: String(localized: "It's the only planner that doesn't yell at me.", bundle: .appLanguage), name: "Sam, 41"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OnbLabel(text: "You're not alone")
                    .padding(.top, 32)

                Text("Thousands are building calmer days with Tempa.")
                    .font(.custom("Nunito-ExtraBold", size: 28).weight(.heavy))
                    .tracking(-0.56)
                    .foregroundColor(T.text)
                    .lineSpacing(-2)
                    .padding(.top, 10)

                // Count card with gradient
                HStack(spacing: 14) {
                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { i in
                            Image("avatar_review_\(i + 1)")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                                .overlay(
                                    Circle().stroke(T.bg, lineWidth: 2.5)
                                )
                                .offset(x: CGFloat(i) * -10)
                                .staggerIn(i, baseDelay: 0.09)
                        }
                    }
                    .padding(.leading, 6)
                    .frame(width: 36 + 3 * (36 - 10))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: "laurel.leading")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(T.textSec)
                            Text("Top 10 ADHD app · App Store 2026")
                                .font(.custom("Nunito-ExtraBold", size: 15).weight(.heavy))
                                .foregroundColor(T.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Image(systemName: "laurel.trailing")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(T.textSec)
                        }
                        HStack(spacing: 5) {
                            HStack(spacing: 2) {
                                ForEach(0..<5, id: \.self) { _ in
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(Cat.routine.ink)
                                }
                            }
                            Text("4.8 · 12,400+ reviews")
                                .font(.custom("Inter-Medium", size: 12).weight(.medium))
                                .foregroundColor(T.textSec)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(lightHex: "#FFE9E1", darkHex: "#2C1F18"), Color(lightHex: "#D6F0E7", darkHex: "#16302A")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                )
                .padding(.top, 22)

                // Testimonials
                VStack(spacing: 10) {
                    ForEach(testimonials.indices, id: \.self) { i in
                        let t = testimonials[i]
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\"\(t.quote)\"")
                                .font(.custom("Nunito-ExtraBold", size: 14).weight(.semibold))
                                .foregroundColor(T.text)
                                .lineSpacing(3)
                            Text("— \(t.name)")
                                .font(.custom("Inter-Medium", size: 12).weight(.semibold))
                                .foregroundColor(T.textSec)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(T.surface)
                        )
                        .tempaShadowSm()
                        .staggerIn(i + 4, baseDelay: 0.09)
                    }
                }
                .padding(.top, 14)

                TempaButton(label: "Continue", variant: .primary, size: .lg, fullWidth: true, showArrow: true) {
                    state.next()
                }
                .padding(.top, 22)
                .padding(.bottom, 50)
            }
            .padding(.horizontal, 22)
        }
    }
}

// MARK: - Screen 7: Forgiveness Promise

struct Onb7ForgiveView: View {
    let state: OnboardingState

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                OnbLabel(text: "A promise")

                Text("No guilt streaks here.")
                    .font(.custom("Nunito-ExtraBold", size: 32).weight(.heavy))
                    .tracking(-0.8)
                    .foregroundColor(T.text)
                    .lineSpacing(-2)
                    .padding(.top, 12)

                Text("Miss a day? Tempa just says: welcome back. We'll pick the next small thing together.")
                    .font(.custom("Inter-Medium", size: 16).weight(.medium))
                    .foregroundColor(T.textSec)
                    .lineSpacing(4)
                    .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 40)

            // Anti-streak card
            VStack(spacing: 10) {
                // "Other apps" row
                HStack(spacing: 12) {
                    Text("🔥")
                        .font(.system(size: 22))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("47-day streak lost")
                            .font(.custom("Nunito-ExtraBold", size: 14).weight(.bold))
                            .foregroundColor(T.textSec)
                            .strikethrough(true, color: T.textSec)
                        Text("Other apps")
                            .font(.custom("Inter-Medium", size: 12).weight(.medium))
                            .foregroundColor(T.textSec)
                    }
                    Spacer()
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(T.textTer)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(T.bgWarm)
                )
                .opacity(0.7)

                // "Tempa" row
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Cat.health.ink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Welcome back. Let's start small.")
                            .font(.custom("Nunito-ExtraBold", size: 15).weight(.bold))
                            .foregroundColor(T.text)
                        Text("Tempa")
                            .font(.custom("Inter-Medium", size: 12).weight(.medium))
                            .foregroundColor(T.textSec)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Cat.health.solid)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Cat.health.bg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Cat.health.solid, lineWidth: 1.5)
                )
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(T.surface)
            )
            .tempaShadowSm()
            .padding(.horizontal, 22)
            .padding(.top, 30)

            Spacer()

            TempaButton(label: "I love that", variant: .primary, size: .lg, fullWidth: true, showArrow: true) {
                state.next()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 50)
        }
    }
}

// MARK: - Screen 8: Notifications

struct Onb8NotifsView: View {
    let state: OnboardingState
    @State private var bannerShown = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                OnbLabel(text: "One last thing")

                Text("Want a gentle nudge for your next block?")
                    .font(.custom("Nunito-ExtraBold", size: 30).weight(.heavy))
                    .tracking(-0.75)
                    .foregroundColor(T.text)
                    .lineSpacing(-2)
                    .padding(.top, 12)

                Text("Soft sound, no buzz, no badges. We promise not to be annoying.")
                    .font(.custom("Inter-Medium", size: 15).weight(.medium))
                    .foregroundColor(T.textSec)
                    .lineSpacing(4)
                    .padding(.top, 12)

                Text("We'll also nudge you before your free trial ends.")
                    .font(.custom("Inter-Medium", size: 13).weight(.medium))
                    .foregroundColor(T.textTer)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 40)

            // Preview notification
            HStack(spacing: 12) {
                Image("tempa_icon_onbording")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Tempa")
                            .font(.custom("Nunito-ExtraBold", size: 13).weight(.heavy))
                            .foregroundColor(T.text)
                        Spacer()
                        Text("now")
                            .font(.custom("Inter-Medium", size: 11).weight(.medium))
                            .foregroundColor(T.textSec)
                    }

                    (Text("In 5 min: ")
                        .font(.custom("Inter-Medium", size: 13).weight(.medium))
                     + Text("Walk + stretch")
                        .font(.custom("Inter-Medium", size: 13).weight(.bold))
                     + Text(". Stand up when you're ready.")
                        .font(.custom("Inter-Medium", size: 13).weight(.medium))
                    )
                    .foregroundColor(T.text)
                    .lineSpacing(2)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(T.surface.opacity(0.85))
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.black.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: Color(red: 40/255, green: 30/255, blue: 20/255).opacity(0.08), radius: 14, x: 0, y: 12)
            .padding(.horizontal, 22)
            .padding(.top, 36)
            // Drops in from the top like a real push notification.
            .opacity(bannerShown ? 1 : 0)
            .offset(y: bannerShown ? 0 : -70)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72).delay(0.3)) {
                    bannerShown = true
                }
            }

            Spacer()

            TempaButton(label: "Allow gentle nudges", variant: .primary, size: .lg, fullWidth: true) {
                requestNotifications()
            }
            .padding(.horizontal, 22)

            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                state.next()
            } label: {
                Text("Maybe later")
                    .font(.custom("Nunito-ExtraBold", size: 14).weight(.bold))
                    .foregroundColor(T.textSec)
            }
            .padding(.top, 12)
            .padding(.bottom, 34)
        }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            Task { @MainActor in
                state.notificationsGranted = granted
                state.next()
            }
        }
    }
}

// MARK: - Screen 9: Building Plan

struct Onb9BuildingView: View {
    let state: OnboardingState
    let settings: SettingsStore

    @State private var currentIdx = 0
    @State private var checkItems: [(String, Bool)] = [
        (String(localized: "Setting your wake time", bundle: .appLanguage), false),
        (String(localized: "Calibrating your energy dip", bundle: .appLanguage), false),
        (String(localized: "Lining up your first focus block", bundle: .appLanguage), false),
        (String(localized: "Picking gentle nudge sounds", bundle: .appLanguage), false),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            TempaWaveform(color: T.primary, maxHeight: 86)
                .frame(height: 110)
                .padding(.horizontal, 50)
                .padding(.bottom, 32)

            Text("Creating your calm day…")
                .font(.custom("Nunito-ExtraBold", size: 26).weight(.heavy))
                .tracking(-0.52)
                .foregroundColor(T.text)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(checkItems.indices, id: \.self) { i in
                    HStack(spacing: 12) {
                        ZStack {
                            if checkItems[i].1 {
                                Circle()
                                    .fill(T.secondary)
                                    .frame(width: 22, height: 22)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            } else if i == currentIdx {
                                SpinnerCircle()
                                    .frame(width: 22, height: 22)
                            } else {
                                Circle()
                                    .stroke(T.textTer, lineWidth: 2)
                                    .frame(width: 22, height: 22)
                            }
                        }
                        .frame(width: 22, height: 22)

                        Text(checkItems[i].0)
                            .font(.custom("Nunito-ExtraBold", size: 14).weight(checkItems[i].1 ? .semibold : .bold))
                            .foregroundColor(checkItems[i].1 ? T.textSec : T.text)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(T.surface)
            )
            .tempaShadowSm()
            .padding(.horizontal, 22)
            .padding(.top, 28)

            Spacer()

            Text("Almost there.")
                .font(.custom("Inter-Medium", size: 13).weight(.semibold))
                .foregroundColor(T.textSec)
                .padding(.bottom, 30)
        }
        .padding(.top, 40)
        .task { await buildPlan() }
    }

    private func buildPlan() async {
        for i in checkItems.indices {
            currentIdx = i
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.easeInOut(duration: 0.3)) {
                checkItems[i].1 = true
            }
        }

        try? await Task.sleep(for: .seconds(0.5))

        settings.wakeTime = state.wakeTime
        settings.energyDipTime = state.energyDipTime
        settings.save()

        state.showPaywall = true
    }
}

// MARK: - Sun Arc

private struct SunArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 12, y: 62))
        p.addQuadCurve(to: CGPoint(x: rect.width - 12, y: 62),
                       control: CGPoint(x: rect.width / 2, y: -26))
        return p
    }
}

// MARK: - Spinner Circle

private struct SpinnerCircle: View {
    @State private var rotating = false

    var body: some View {
        Circle()
            .trim(from: 0.2, to: 1)
            .stroke(T.primary, lineWidth: 2)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: rotating)
            .onAppear { rotating = true }
    }
}
