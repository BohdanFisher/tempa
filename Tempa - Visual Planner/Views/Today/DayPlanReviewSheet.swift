import SwiftUI
import CoreData

/// One editable row in the day-plan review.
struct PlanRow: Identifiable {
    let id = UUID()
    var title: String
    var start: Date
    var durationMinutes: Int
    var category: String
    var icon: String
}

/// Takes a spoken brain-dump, asks the AI to split it into separate scheduled
/// tasks, lets the user review/tweak them, then adds them all at once.
struct DayPlanReviewSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let dump: String
    let onAdded: () -> Void

    @State private var rows: [PlanRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var started = false

    private let apiClient = ClaudeAPIClient()
    private let categories = ["work", "personal", "health", "routine", "social", "rest"]

    var body: some View {
        NavigationStack {
            ZStack {
                T.bg.ignoresSafeArea()
                if isLoading {
                    loadingView
                } else if let err = errorMessage {
                    errorView(err)
                } else {
                    content
                }
            }
            .navigationTitle("Your day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            // Unstructured Task so the request isn't cancelled by the cover transition
            // (a structured .task here fails the first call, then works on retry).
            guard !started else { return }
            started = true
            Task { await load() }
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(T.surface)
                        .frame(height: 70)
                        .tempaShadowSm()
                }
            }
            .padding(.horizontal, 20)

            HStack(spacing: 8) {
                ProgressView().tint(T.primary)
                Text("Sorting what you said into tasks…")
                    .font(.custom(T.fontHeader, size: 14).weight(.semibold))
                    .foregroundColor(T.textSec)
            }
            .padding(.top, 8)
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 38))
                .foregroundColor(T.textTer)
            Text(msg)
                .font(.custom(T.fontBody, size: 15))
                .foregroundColor(T.textSec)
                .multilineTextAlignment(.center)
            Button {
                Task { await load() }
            } label: {
                Text("Try again")
                    .font(.custom(T.fontHeader, size: 15).weight(.bold))
                    .foregroundColor(T.primary)
            }
        }
        .padding(40)
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(rows.count) TASK\(rows.count == 1 ? "" : "S") · TAP TO TWEAK")
                        .font(.custom(T.fontHeader, size: 12).weight(.heavy))
                        .tracking(1.2)
                        .foregroundColor(T.textSec)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 2)

                    ForEach($rows) { $row in
                        planRow($row)
                    }
                }
                .padding(20)
                .padding(.bottom, 120)
            }

            addBar
        }
    }

    private func planRow(_ row: Binding<PlanRow>) -> some View {
        let cc = Cat.named(row.wrappedValue.category)
        return VStack(spacing: 12) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(categories, id: \.self) { c in
                        Button { row.wrappedValue.category = c } label: {
                            if c == row.wrappedValue.category {
                                Label(c.capitalized, systemImage: "checkmark")
                            } else {
                                Text(c.capitalized)
                            }
                        }
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(cc.bg)
                            .frame(width: 34, height: 34)
                        Image(systemName: row.wrappedValue.icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(cc.ink)
                    }
                }

                TextField("Task", text: row.title, axis: .vertical)
                    .font(.custom(T.fontHeader, size: 15).weight(.bold))
                    .foregroundColor(T.text)
                    .lineLimit(1...2)

                Spacer(minLength: 6)

                Button {
                    withAnimation { rows.removeAll { $0.id == row.wrappedValue.id } }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 19))
                        .foregroundColor(T.textTer)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                DatePicker("", selection: row.start, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(T.primary)
                    .fixedSize()

                Spacer()

                Menu {
                    ForEach([15, 20, 30, 45, 60, 90, 120], id: \.self) { m in
                        Button { row.wrappedValue.durationMinutes = m } label: {
                            if row.wrappedValue.durationMinutes == m {
                                Label(durationText(m), systemImage: "checkmark")
                            } else {
                                Text(durationText(m))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass").font(.system(size: 11, weight: .medium))
                        Text(durationText(row.wrappedValue.durationMinutes))
                            .font(.custom(T.fontHeader, size: 12).weight(.bold))
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.4)
                    }
                    .foregroundColor(T.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(T.bgWarm))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cc.bg, lineWidth: 1)
        )
        .tempaShadowSm()
    }

    private var addBar: some View {
        VStack(spacing: 0) {
            if !rows.isEmpty {
                TempaButton(label: "Add \(rows.count) task\(rows.count == 1 ? "" : "s") to my day",
                            variant: .primary, size: .lg, fullWidth: true, showArrow: true) {
                    addAll()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .background(
            LinearGradient(colors: [T.bg.opacity(0), T.bg], startPoint: .top, endPoint: .init(x: 0.5, y: 0.5))
        )
    }

    // MARK: - Logic

    private func load() async {
        isLoading = true
        errorMessage = nil
        for attempt in 0..<2 {
            do {
                let plan = try await apiClient.planTasks(from: dump)
                let built = buildRows(from: plan)
                if built.isEmpty {
                    errorMessage = "Couldn't pick out any tasks. Want to try saying it again?"
                } else {
                    rows = built
                }
                isLoading = false
                return
            } catch {
                #if DEBUG
                print("[Tempa] planTasks attempt \(attempt + 1) failed:", error)
                #endif
                if attempt == 0 {
                    try? await Task.sleep(nanoseconds: 500_000_000)   // brief pause, retry once
                    continue
                }
                errorMessage = "Something went wrong reading your day. Tap to retry."
            }
        }
        isLoading = false
    }

    private func buildRows(from plan: DayPlan) -> [PlanRow] {
        var cursor = nextHalfHour()
        var result: [PlanRow] = []
        for t in plan.tasks {
            let dur = min(max(t.durationMinutes ?? 30, 5), 240)
            let start: Date
            if t.hasTime == true, let concrete = ScheduleResolver.concreteStart(date: t.date, time: t.time) {
                start = concrete
                cursor = max(cursor, concrete.addingTimeInterval(TimeInterval(dur) * 60))
            } else {
                start = cursor
                cursor = cursor.addingTimeInterval(TimeInterval(dur) * 60)
            }
            let cat = validCategory(t.category)
            result.append(PlanRow(title: t.title, start: start, durationMinutes: dur, category: cat, icon: validIcon(t.icon)))
        }
        return result.sorted { $0.start < $1.start }
    }

    private func addAll() {
        for row in rows {
            let trimmed = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let task = TaskBlock(context: viewContext)
            task.id = UUID()
            task.title = trimmed
            task.iconName = row.icon
            task.category = row.category
            task.startTime = row.start
            task.durationMinutes = Int32(row.durationMinutes)
            task.priority = 0
            task.createdAt = Date()
        }
        try? viewContext.save()
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        dismiss()
        onAdded()
    }

    private func validCategory(_ c: String?) -> String {
        let lc = (c ?? "personal").lowercased()
        return categories.contains(lc) ? lc : "personal"
    }

    private func validIcon(_ icon: String?) -> String {
        if let icon, !icon.trimmingCharacters(in: .whitespaces).isEmpty, icon.lowercased() != "null" {
            return icon
        }
        return "circle"   // same fallback as a manually-created task
    }

    private func durationText(_ m: Int) -> String {
        m >= 60 ? (m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m") : "\(m)m"
    }

    private func nextHalfHour() -> Date {
        let cal = Calendar.current
        let now = Date()
        let m = cal.component(.minute, from: now)
        let addMin = (m < 30 ? 30 : 60) - m
        return cal.date(byAdding: .minute, value: addMin, to: now) ?? now
    }
}
