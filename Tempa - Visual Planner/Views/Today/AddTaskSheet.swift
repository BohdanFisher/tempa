import SwiftUI
import CoreData

struct AddTaskSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var selectedCategory = "personal"
    @State private var startTime = Self.nextRoundedQuarter()
    @State private var durationMinutes: Double = 30
    @State private var selectedPriority = 0   // 0 none · 1 low · 2 medium · 3 high
    @State private var breakdownSteps: [MicroStepData] = []
    @State private var isThinking = false
    @State private var showVoice = false
    @State private var showAskAI = false
    @State private var dumpText = ""
    @State private var showDayPlan = false
    @State private var pendingPlan = false
    @State private var titleShake: CGFloat = 0   // gentle "needs a title" nudge
    @FocusState private var titleFocused: Bool

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()
                .onTapGesture { titleFocused = false }

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        inputCard

                        CategorySection(category: $selectedCategory)
                        WhenSection(startTime: $startTime)
                        DurationSection(minutes: $durationMinutes)
                        PrioritySection(priority: $selectedPriority)

                        primaryActions
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 130)
                    .contentShape(Rectangle())
                    .onTapGesture { titleFocused = false }   // tap empty space to dismiss keyboard
                }
                .scrollDismissesKeyboard(.immediately)

                if !breakdownSteps.isEmpty {
                    footerActions
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                titleFocused = true
            }
        }
        .fullScreenCover(isPresented: $showVoice) {
            // Voice is a brain-dump → split into several scheduled tasks ("plan my day").
            AddTaskVoiceView { text in
                dumpText = text
                pendingPlan = true
            }
        }
        .onChange(of: showVoice) { _, shown in
            // Present the day-plan once the voice sheet has fully dismissed.
            if !shown && pendingPlan {
                pendingPlan = false
                showDayPlan = true
            }
        }
        .fullScreenCover(isPresented: $showDayPlan) {
            DayPlanReviewSheet(dump: dumpText) { dismiss() }
        }
        .fullScreenCover(isPresented: $showAskAI) {
            // Ask Tempa's confirmed task → same plan flow as voice, so it actually schedules.
            AddTaskAskAIView { text in
                dumpText = text
                pendingPlan = true
            }
        }
        .onChange(of: showAskAI) { _, shown in
            if !shown && pendingPlan {
                pendingPlan = false
                showDayPlan = true
            }
        }
        .onChange(of: selectedCategory) { _, new in
            // Re-tint any already-generated steps so changing the type is reflected live.
            breakdownSteps = breakdownSteps.map {
                MicroStepData(title: $0.title, minutes: $0.minutes, icon: $0.icon, category: new)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(T.text)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(T.surface)
                    )
                    .tempaShadowSm()
            }

            Spacer()

            Text("New task")
                .font(.custom(T.fontHeader, size: 17).weight(.heavy))
                .foregroundColor(T.text)

            Spacer()
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Title card (with the create-only AI input methods)

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("WHAT'S ON YOUR MIND")
                    .font(.custom(T.fontBody, size: 12).weight(.semibold))
                    .tracking(0.7)
                    .foregroundColor(T.textSec)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                    Text("AI")
                        .font(.custom(T.fontHeader, size: 11).weight(.heavy))
                        .tracking(0.5)
                }
                .foregroundColor(T.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(lightHex: "#FFE9E1", darkHex: "#2C1F18"), Color(lightHex: "#D6F0E7", darkHex: "#16302A")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                )
            }

            TextField("", text: $title, axis: .vertical)
                .font(.custom(T.fontHeader, size: 22).weight(.bold))
                .tracking(-0.2)
                .foregroundColor(T.text)
                .tint(T.primary)
                .lineLimit(1...4)
                .focused($titleFocused)
                .submitLabel(.done)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(GentleShake(animatableData: titleShake))

            Divider()
                .padding(.top, 8)

            HStack(spacing: 8) {
                aiInputButton(icon: "mic.fill", label: "Speak it") { showVoice = true }
                aiInputButton(icon: "sparkles", label: "Ask Tempa") { showAskAI = true }
            }
            .padding(.top, 6)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(T.surface)
        )
        .tempaShadowSm()
    }

    private func aiInputButton(icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium))
                Text(label).font(.custom(T.fontHeader, size: 13).weight(.bold))
            }
            .foregroundColor(T.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(T.bgWarm))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Primary actions (create-only: add + AI breakdown into steps)

    private var primaryActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            TempaButton(label: "Add task", variant: .primary, size: .lg, fullWidth: true, showArrow: true) {
                saveSingleTask()
            }

            if !title.trimmingCharacters(in: .whitespaces).isEmpty && breakdownSteps.isEmpty && !isThinking {
                breakIntoStepsButton
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if isThinking || !breakdownSteps.isEmpty {
                aiBreakdownSection
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isThinking)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: breakdownSteps.count)
    }

    // The AI alternative to a quick add — a clearly secondary card so it reads as
    // "the other option" rather than a second primary button competing with Add task.
    private var breakIntoStepsButton: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            runBreakdown()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(lightHex: "#FFE9E1", darkHex: "#3A2A20"), Color(lightHex: "#D6F0E7", darkHex: "#1B342E")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(T.primary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Break it into small steps")
                        .font(.custom(T.fontHeader, size: 15).weight(.bold))
                        .foregroundColor(T.text)
                    Text("Feeling stuck? Let Tempa split it up.")
                        .font(.custom(T.fontBody, size: 12).weight(.medium))
                        .foregroundColor(T.textSec)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(T.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(T.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(T.primary.opacity(0.35), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - AI Breakdown (micro-steps of one task)

    private var aiBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(lightHex: "#FFE9E1", darkHex: "#2C1F18"), Color(lightHex: "#D6F0E7", darkHex: "#16302A")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(T.primary)
                        )

                    Text("Break it down")
                        .font(.custom(T.fontHeader, size: 17).weight(.heavy))
                        .foregroundColor(T.text)
                }

                Spacer()

                if !breakdownSteps.isEmpty {
                    Text("\(breakdownSteps.count) small steps · \(breakdownSteps.reduce(0) { $0 + $1.minutes }) min total")
                        .font(.custom(T.fontBody, size: 12).weight(.semibold))
                        .foregroundColor(T.textSec)
                } else if isThinking {
                    Text("Thinking…")
                        .font(.custom(T.fontBody, size: 12).weight(.semibold))
                        .foregroundColor(T.textSec)
                }
            }

            if isThinking {
                VStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(T.surface)
                            .frame(height: 64)
                            .tempaShadowSm()
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(breakdownSteps.enumerated()), id: \.offset) { i, step in
                        MicroStepRow(index: i + 1, step: step)
                    }
                }
            }
        }
    }

    // MARK: - Footer (only while micro-steps are shown)

    private var footerActions: some View {
        HStack(spacing: 10) {
            TempaButton(label: "Re-do", variant: .ghost, size: .md, fullWidth: true) {
                runBreakdown()
            }
            .frame(width: 110)

            TempaButton(label: "Add \(breakdownSteps.count) steps", variant: .primary, size: .md, fullWidth: true, showArrow: true) {
                saveSteps()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .padding(.bottom, 20)
        .background(
            LinearGradient(
                colors: [T.bg.opacity(0), T.bg],
                startPoint: .top, endPoint: .init(x: 0.5, y: 0.4)
            )
        )
    }

    // MARK: - Logic

    private let apiClient = ClaudeAPIClient()

    private func runBreakdown() {
        let raw = title.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        titleFocused = false
        isThinking = true
        breakdownSteps = []

        Task { @MainActor in
            let result: TaskBreakdown
            do {
                result = try await apiClient.breakDown(task: raw)
            } catch {
                result = FallbackBreakdown.generate(for: raw)
            }

            // Set the start time from what the user said — an exact time/day,
            // or a free hour-slot inside a vague window ("ввечері", "після обіду").
            if let resolved = ScheduleResolver.resolve(result.schedule, context: viewContext) {
                startTime = resolved
            }
            // Drop the spoken time words out of the title for the header.
            if let clean = result.cleanTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !clean.isEmpty {
                title = clean
            }

            breakdownSteps = result.steps.map { step in
                MicroStepData(title: step.title, minutes: step.duration, icon: step.icon, category: selectedCategory)
            }
            isThinking = false
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        }
    }

    private func saveSteps() {
        var cursor = startTime
        for step in breakdownSteps {
            let task = TaskBlock(context: viewContext)
            task.id = UUID()
            task.title = step.title
            task.iconName = step.icon
            task.category = selectedCategory
            task.startTime = cursor
            task.durationMinutes = Int32(step.minutes)
            task.priority = Int16(selectedPriority)
            task.createdAt = Date()
            cursor = cursor.addingTimeInterval(TimeInterval(step.minutes) * 60)  // back-to-back
        }
        try? viewContext.save()
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
        dismiss()
    }

    private func saveSingleTask() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // No title yet — a soft shake instead of silence, never a scold.
            withAnimation(.easeInOut(duration: 0.4)) { titleShake += 1 }
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            #endif
            titleFocused = true
            return
        }
        let task = TaskBlock(context: viewContext)
        task.id = UUID()
        task.title = trimmed
        task.iconName = Cat.icon(for: selectedCategory)
        task.category = selectedCategory
        task.startTime = startTime
        task.durationMinutes = Int32(durationMinutes)
        task.priority = Int16(selectedPriority)
        task.createdAt = Date()
        try? viewContext.save()
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
        dismiss()
    }

    private static func nextRoundedQuarter() -> Date {
        let cal = Calendar.current
        let now = Date()
        let minute = cal.component(.minute, from: now)
        let next = ((minute / 15) + 1) * 15
        return cal.date(bySetting: .minute, value: next % 60, of: now) ?? now
    }
}

struct MicroStepData {
    let title: String
    let minutes: Int
    let icon: String
    let category: String
}

struct MicroStepRow: View {
    let index: Int
    let step: MicroStepData

    var body: some View {
        let cc = Cat.named(step.category)
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.custom(T.fontHeader, size: 12).weight(.heavy))
                .foregroundColor(T.textSec)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(T.bgWarm)
                )

            Image(systemName: step.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(cc.ink)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(cc.bg)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .font(.custom(T.fontHeader, size: 15).weight(.bold))
                    .foregroundColor(T.text)
                Text("\(step.minutes) min")
                    .font(.custom(T.fontBody, size: 12).weight(.medium))
                    .foregroundColor(T.textSec)
            }

            Spacer()

            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(T.textTer)
                        .frame(width: 14, height: 1.5)
                }
            }
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(T.surface)
        )
        .tempaShadowSm()
    }
}

#Preview {
    AddTaskSheet()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
