import SwiftUI
import CoreData
import Combine

struct NowNextView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @FetchRequest private var tasks: FetchedResults<TaskBlock>
    @State private var now = Date()
    @State private var viewMode = 1
    @State private var breatheScale: CGFloat = 1.0

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        _tasks = FetchRequest(
            sortDescriptors: [SortDescriptor(\TaskBlock.startTime, order: .forward)],
            predicate: NSPredicate(
                format: "startTime >= %@ AND startTime < %@ AND isCompleted == NO",
                start as NSDate, end as NSDate
            )
        )
    }

    private var currentTask: TaskBlock? {
        tasks.first { t in
            guard let s = t.startTime else { return false }
            let e = s.addingTimeInterval(TimeInterval(t.durationMinutes) * 60)
            return now >= s && now < e
        }
    }
    private var nextTask: TaskBlock? {
        tasks.first { t in
            guard let s = t.startTime else { return false }
            return s > now
        }
    }

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 8)
                    .padding(.bottom, 0)

                ScrollView {
                    VStack(spacing: 0) {
                        if let current = currentTask {
                            nowSection(current)
                        } else {
                            freeCard
                        }

                        if let next = nextTask {
                            nextSection(next)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .onReceive(timer) { _ in now = Date() }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                breatheScale = 1.08
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            HStack(spacing: 2) {
                ForEach(["Today", "Now"], id: \.self) { label in
                    let idx = label == "Today" ? 0 : 1
                    let isSelected = viewMode == idx
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { viewMode = idx }
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    } label: {
                        Text(label)
                            .font(.custom(T.fontHeader, size: 13).weight(.bold))
                            .foregroundColor(isSelected ? T.text : T.textSec)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(isSelected ? .white : .clear)
                                    .shadow(color: isSelected ? Color(red: 40/255, green: 30/255, blue: 20/255).opacity(0.05) : .clear, radius: 4, x: 0, y: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(lightHex: "#EFE9DD", darkHex: "#2A231D"))
            )

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(T.textSec)
                Text(now.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(T.text)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - NOW Section

    private func nowSection(_ task: TaskBlock) -> some View {
        let start = task.startTime ?? now
        let total = TimeInterval(task.durationMinutes) * 60
        let elapsed = now.timeIntervalSince(start)
        let pct = min(max(elapsed / total, 0), 1)
        let remaining = max(0, Int((total - elapsed) / 60))
        let cc = Cat.named(task.category ?? "work")
        let endTime = start.addingTimeInterval(total)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PulseDot(size: 8, color: cc.ink, rings: 2, speed: 3)
                Text("RIGHT NOW")
                    .font(.custom(T.fontHeader, size: 11).weight(.heavy))
                    .tracking(2)
                    .foregroundColor(cc.ink)
            }
            .padding(.top, 24)

            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(T.surface)
                                .frame(width: 56, height: 56)
                            Image(systemName: task.iconName ?? "circle")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundColor(cc.ink)
                        }
                        .tempaShadowSm()

                        Text("Work · Deep focus")
                            .font(.custom(T.fontHeader, size: 12).weight(.bold))
                            .tracking(1)
                            .foregroundColor(cc.ink)
                            .textCase(.uppercase)
                    }

                    Text(task.title ?? "Current task")
                        .font(.custom(T.fontHeader, size: 30).weight(.heavy))
                        .tracking(-0.6)
                        .foregroundColor(T.text)
                        .lineSpacing(2)
                        .padding(.top, 28)

                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.5), lineWidth: 5)
                            Circle()
                                .trim(from: 0, to: pct)
                                .stroke(cc.ink, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(Int(pct * 100))%")
                                .font(.custom(T.fontHeader, size: 14).weight(.heavy))
                                .foregroundColor(cc.ink)
                        }
                        .frame(width: 56, height: 56)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(remaining > 60 ? "\(remaining/60) h left" : "\(remaining) min left")
                                .font(.custom(T.fontHeader, size: 13).weight(.bold))
                                .foregroundColor(cc.ink.opacity(0.7))
                            Text("Ends at \(endTime.formatted(.dateTime.hour().minute()))")
                                .font(.custom(T.fontHeader, size: 20).weight(.heavy))
                                .tracking(-0.2)
                                .foregroundColor(T.text)
                        }
                    }
                    .padding(.top, 24)
                }
                .padding(22)

                Circle()
                    .stroke(cc.solid.opacity(0.4), lineWidth: 2)
                    .frame(width: 220, height: 220)
                    .scaleEffect(reduceMotion ? 1 : breatheScale)
                    .offset(x: 60, y: -60)
                    .clipped()

                Circle()
                    .fill(cc.solid.opacity(0.18))
                    .frame(width: 160, height: 160)
                    .offset(x: 30, y: -30)
                    .clipped()
            }
            .frame(minHeight: 280)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(cc.bg)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            HStack(spacing: 10) {
                TempaButton(label: "Focus mode", variant: .primary, size: .md) {}
                    .frame(maxWidth: .infinity)
                TempaButton(label: "Done", variant: .ghost, size: .md) {
                    completeTask(task)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 0)
        }
    }

    // MARK: - NEXT Section

    private func nextSection(_ task: TaskBlock) -> some View {
        let cc = Cat.named(task.category ?? "work")
        let minutesUntil = task.startTime.map { max(0, Int($0.timeIntervalSince(now) / 60)) } ?? 0
        let hourStr = minutesUntil >= 60 ? "\(minutesUntil / 60)h" : "\(minutesUntil)m"

        return VStack(alignment: .leading, spacing: 8) {
            Text("THEN · IN \(hourStr.uppercased())")
                .font(.custom(T.fontHeader, size: 11).weight(.heavy))
                .tracking(2)
                .foregroundColor(T.textSec)
                .padding(.top, 8)

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(cc.bg)
                        .frame(width: 48, height: 48)
                    Image(systemName: task.iconName ?? "circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(cc.ink)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title ?? "Next up")
                        .font(.custom(T.fontHeader, size: 16).weight(.bold))
                        .foregroundColor(T.text)
                    Text("\(task.startTime?.formatted(.dateTime.hour().minute()) ?? "") · \(task.durationMinutes) min")
                        .font(.custom(T.fontBody, size: 12).weight(.medium))
                        .foregroundColor(T.textSec)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(T.textTer)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(T.surface)
            )
            .tempaShadowSm()
        }
    }

    // MARK: - Free / Done

    private var freeCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 48))
                .foregroundColor(Cat.routine.solid)

            Text("You're free right now")
                .font(.custom(T.fontHeader, size: 22).weight(.heavy))
                .foregroundColor(T.text)

            Text("Enjoy the moment, or tap + to add something.")
                .font(.custom(T.fontBody, size: 15).weight(.medium))
                .foregroundColor(T.textSec)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(T.surface)
        )
        .tempaShadow()
        .padding(.top, 24)
    }

    private func completeTask(_ task: TaskBlock) {
        task.isCompleted = true
        task.completedAt = Date()
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
        try? viewContext.save()
    }
}

#Preview {
    NowNextView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
