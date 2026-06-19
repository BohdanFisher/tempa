import SwiftUI
import CoreData

struct TaskBreakdownSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    private let apiClient: ClaudeAPIClient
    private let rateLimiter = BreakdownRateLimiter()

    @State private var taskText = ""
    @State private var steps: [TaskBreakdown.Step] = []
    @State private var isLoading = false
    @State private var usedFallback = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    init(apiClient: ClaudeAPIClient = ClaudeAPIClient()) {
        self.apiClient = apiClient
    }

    var body: some View {
        NavigationStack {
            ZStack {
                T.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        inputSection
                        if isLoading { loadingView }
                        if let err = errorMessage { banner(err) }
                        if !steps.isEmpty {
                            stepsSection
                            addAllButton
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(T.text)
                            .frame(width: 34, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(T.surface)
                            )
                    }
                }
            }
            .onAppear { focused = true }
        }
    }

    // MARK: - Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What are you avoiding?")
                .font(.custom(T.fontHeader, size: 22).weight(.heavy))
                .tracking(-0.3)
                .foregroundColor(T.text)

            TextField("e.g. Clean the apartment", text: $taskText, axis: .vertical)
                .font(.custom(T.fontBody, size: 17).weight(.medium))
                .foregroundColor(T.text)
                .lineLimit(1...4)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(T.surface)
                )
                .tempaShadowSm()
                .focused($focused)

            TempaButton(
                label: "Break it down",
                variant: .primary,
                size: .lg,
                fullWidth: true
            ) {
                Task { await breakDown() }
            }
            .opacity(taskText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            .disabled(taskText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            PulseDot(size: 16, color: T.primary, rings: 3, speed: 2)
            Text("Breaking it down...")
                .font(.custom(T.fontHeader, size: 15).weight(.semibold))
                .foregroundColor(T.textSec)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Banner

    private func banner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundColor(T.textSec)
            Text(message)
                .font(.custom(T.fontBody, size: 13).weight(.medium))
                .foregroundColor(T.textSec)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: T.r.sm, style: .continuous)
                .fill(T.bgWarm)
        )
    }

    // MARK: - Steps (MicroStep cards)

    private var stepsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("See? Not so scary.")
                    .font(.custom(T.fontHeader, size: 16).weight(.bold))
                    .foregroundColor(T.text)
                Spacer()
            }
            .padding(.bottom, 4)

            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                MicroStepCard(step: step, index: i + 1) {
                    steps.remove(at: i)
                }
            }
        }
    }

    // MARK: - Add All

    private var addAllButton: some View {
        TempaButton(label: "Add all to today", variant: .secondary, size: .lg, fullWidth: true) {
            addAllToToday()
        }
    }

    // MARK: - Logic

    private func breakDown() async {
        let trimmed = taskText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        steps = []
        errorMessage = nil
        usedFallback = false
        focused = false

        let isPro = false

        guard rateLimiter.canUse(isPro: isPro) else {
            isLoading = false
            errorMessage = "You've used all 3 free breakdowns today. Upgrade for unlimited."
            steps = FallbackBreakdown.generate(for: trimmed).steps
            usedFallback = true
            return
        }

        do {
            let result = try await apiClient.breakDown(task: trimmed)
            steps = result.steps
            rateLimiter.recordUse()
        } catch {
            steps = FallbackBreakdown.generate(for: trimmed).steps
            usedFallback = true
            errorMessage = "Working offline — here's a generic plan. Edit as needed."
        }

        isLoading = false
    }

    private func addAllToToday() {
        var start = Date()
        let cal = Calendar.current
        let min = cal.component(.minute, from: start)
        let rounded = ((min / 5) + 1) * 5
        start = cal.date(bySetting: .minute, value: rounded % 60, of: start) ?? start

        let cats = Cat.all
        for (i, step) in steps.enumerated() {
            let task = TaskBlock(context: viewContext)
            task.id = UUID()
            task.title = step.title
            task.iconName = step.icon
            let cat = cats[i % cats.count]
            task.category = cat.0
            task.colorHex = "#E3EDFF"
            task.startTime = start
            task.durationMinutes = Int32(step.duration)
            task.createdAt = Date()
            start = start.addingTimeInterval(TimeInterval(step.duration) * 60)
        }

        try? viewContext.save()
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        dismiss()
    }
}

// MARK: - MicroStep Card

struct MicroStepCard: View {
    let step: TaskBreakdown.Step
    let index: Int
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Index circle
            Text("\(index)")
                .font(.custom(T.fontHeader, size: 12).weight(.heavy))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(T.primary))

            // Icon
            Image(systemName: step.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Cat.work.ink)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Cat.work.bg)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.custom(T.fontHeader, size: 14).weight(.bold))
                    .foregroundColor(T.text)
                Text("\(step.duration) min")
                    .font(.custom(T.fontBody, size: 12).weight(.medium))
                    .foregroundColor(T.textSec)
            }

            Spacer()

            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14))
                .foregroundColor(T.textTer)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(T.textSec)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(T.surface)
        )
        .tempaShadowSm()
    }
}

#Preview {
    TaskBreakdownSheet()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
