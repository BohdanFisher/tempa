import SwiftUI
import CoreData
import Combine

struct TodayView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @FetchRequest private var tasks: FetchedResults<TaskBlock>
    @State private var router = AppRouter.shared
    @State private var showingAddTask = false
    @State private var now = Date()
    @State private var breatheScale: CGFloat = 1.0
    @State private var showCompleted = false
    @AppStorage("todayGrouping") private var grouping: TodayGrouping = .none
    @AppStorage("todaySorting") private var sorting: TodaySorting = .time

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        _tasks = FetchRequest(
            sortDescriptors: [SortDescriptor(\TaskBlock.startTime, order: .forward)],
            predicate: NSPredicate(format: "startTime >= %@ AND startTime < %@", start as NSDate, end as NSDate),
            animation: .default
        )
    }

    private var completedCount: Int { tasks.filter(\.isCompleted).count }
    private var activeTasks: [TaskBlock] { tasks.filter { !$0.isCompleted } }
    private var doneTasks: [TaskBlock] { tasks.filter(\.isCompleted) }
    private var currentTask: TaskBlock? {
        tasks.first { t in
            guard !t.isCompleted, let s = t.startTime else { return false }
            let e = s.addingTimeInterval(TimeInterval(t.durationMinutes) * 60)
            return now >= s && now < e
        }
    }
    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: now)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            T.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    greetingSection
                    dayPulseCard
                    if let current = currentTask {
                        nowHero(current)
                            .padding(.bottom, 8)
                    }
                    timelineSection
                }
                .padding(.bottom, 140)
            }

            fab
        }
        .confettiHost()
        .onReceive(timer) { _ in now = Date() }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                breatheScale = 1.08
            }
        }
        .fullScreenCover(isPresented: $showingAddTask) {
            AddTaskSheet()
        }
        .onChange(of: router.addTaskRequest) { _, req in
            // e.g. Welcome Back's "Plan something small" → open the add-task sheet.
            guard req != nil else { return }
            router.addTaskRequest = nil   // consume
            showingAddTask = true
        }
    }

    // MARK: - "Right now" spotlight

    private func nowHero(_ task: TaskBlock) -> some View {
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
            .padding(.top, 18)

            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(T.surface)
                                .frame(width: 50, height: 50)
                            Image(systemName: task.iconName ?? "circle")
                                .font(.system(size: 23, weight: .medium))
                                .foregroundColor(cc.ink)
                        }
                        .tempaShadowSm()

                        Text((task.category ?? "Task").capitalized)
                            .font(.custom(T.fontHeader, size: 12).weight(.bold))
                            .tracking(1)
                            .foregroundColor(cc.ink)
                            .textCase(.uppercase)
                    }

                    Text(task.title ?? "Current task")
                        .font(.custom(T.fontHeader, size: 26).weight(.heavy))
                        .tracking(-0.5)
                        .foregroundColor(T.text)
                        .lineSpacing(2)
                        .padding(.top, 20)

                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.5), lineWidth: 5)
                            Circle()
                                .trim(from: 0, to: pct)
                                .stroke(cc.ink, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(Int(pct * 100))%")
                                .font(.custom(T.fontHeader, size: 13).weight(.heavy))
                                .foregroundColor(cc.ink)
                        }
                        .frame(width: 50, height: 50)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(remaining > 60 ? "\(remaining/60) hour\(remaining/60 > 1 ? "s" : "") left" : "\(remaining) min left")
                                .font(.custom(T.fontHeader, size: 13).weight(.bold))
                                .foregroundColor(cc.ink.opacity(0.7))
                            Text("Ends at \(endTime.formatted(.dateTime.hour().minute()))")
                                .font(.custom(T.fontHeader, size: 18).weight(.heavy))
                                .tracking(-0.2)
                                .foregroundColor(T.text)
                        }
                    }
                    .padding(.top, 18)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)

                Circle()
                    .stroke(cc.solid.opacity(0.4), lineWidth: 2)
                    .frame(width: 200, height: 200)
                    .scaleEffect(reduceMotion ? 1 : breatheScale)
                    .offset(x: 60, y: -60)

                Circle()
                    .fill(cc.solid.opacity(0.18))
                    .frame(width: 150, height: 150)
                    .offset(x: 34, y: -30)
            }
            .frame(minHeight: 230)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(cc.bg)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            HStack(spacing: 10) {
                TempaButton(label: "Focus mode", variant: .primary, size: .md) {
                    AppRouter.shared.selectedTab = .focus
                }
                .frame(maxWidth: .infinity)
                TempaButton(label: "Done", variant: .ghost, size: .md) {
                    toggleCompletion(task)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Greeting

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(dateString)
                    .font(.custom(T.fontHeader, size: 26).weight(.heavy))
                    .tracking(-0.4)
                    .foregroundColor(T.text)

                Spacer()

                organizeMenu
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var isOrganizing: Bool { grouping != .none || sorting != .time }

    private var organizeMenu: some View {
        Menu {
            Section("Group by") {
                Picker("Group by", selection: $grouping) {
                    ForEach(TodayGrouping.allCases, id: \.self) { g in
                        Label(g.label, systemImage: g.icon).tag(g)
                    }
                }
                .pickerStyle(.inline)
            }
            Section("Sort by") {
                Picker("Sort by", selection: $sorting) {
                    ForEach(TodaySorting.allCases, id: \.self) { s in
                        Label(s.label, systemImage: s.icon).tag(s)
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(T.text)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(T.surface)
                    )
                    .tempaShadowSm()
                if isOrganizing {
                    Circle()
                        .fill(T.primary)
                        .frame(width: 8, height: 8)
                        .offset(x: -6, y: 6)
                }
            }
        }
    }

    // MARK: - Day Pulse Card

    private var dayPulseCard: some View {
        HStack(spacing: 12) {
            PulseDot(size: 10, color: T.primary, rings: 2, speed: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text("Your tempo today")
                    .font(.custom(T.fontBody, size: 13).weight(.medium))
                    .foregroundColor(T.textSec)
                Text("\(completedCount) of \(tasks.count) done · steady pace")
                    .font(.custom(T.fontHeader, size: 14).weight(.bold))
                    .foregroundColor(T.text)
            }

            Spacer()

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(lightHex: "#EAE5DA", darkHex: "#2E2722"))
                    .frame(width: 70, height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(T.secondary)
                    .frame(width: tasks.isEmpty ? 0 : 70 * CGFloat(completedCount) / CGFloat(tasks.count), height: 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(T.surface)
        )
        .tempaShadowSm()
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(spacing: 0) {
            if tasks.isEmpty {
                emptyTimeline
            } else {
                if activeTasks.isEmpty {
                    allDoneCard
                } else {
                    activeContent
                }

                if !doneTasks.isEmpty {
                    doneSection
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var activeContent: some View {
        if grouping == .none {
            let list = sortTasks(activeTasks)
            ForEach(list) { task in
                TimelineRow(task: task, now: now, isLast: task == list.last) {
                    toggleCompletion(task)
                }
            }
        } else {
            ForEach(groupedActive()) { group in
                groupHeader(group.title, group.tasks.count)
                ForEach(group.tasks) { task in
                    TimelineRow(task: task, now: now, isLast: task == group.tasks.last) {
                        toggleCompletion(task)
                    }
                }
            }
        }
    }

    private func groupHeader(_ title: String, _ count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.custom(T.fontHeader, size: 12).weight(.bold))
                .tracking(0.6)
                .foregroundColor(T.textSec)
            Text("\(count)")
                .font(.custom(T.fontBody, size: 12).weight(.bold))
                .foregroundColor(T.textTer)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(T.surface))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Done (collapsed) section

    private var doneSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showCompleted.toggle() }
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(T.secondary)
                    Text("Done today · \(doneTasks.count)")
                        .font(.custom(T.fontHeader, size: 14).weight(.bold))
                        .foregroundColor(T.textSec)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(T.textTer)
                        .rotationEffect(.degrees(showCompleted ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(T.surface)
                )
                .tempaShadowSm()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, activeTasks.isEmpty ? 0 : 12)

            if showCompleted {
                VStack(spacing: 0) {
                    ForEach(doneTasks) { task in
                        TimelineRow(task: task, now: now, isLast: task == doneTasks.last) {
                            toggleCompletion(task)
                        }
                    }
                }
                .padding(.top, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var allDoneCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 38))
                .foregroundColor(T.secondary)
            Text("All done for today")
                .font(.custom(T.fontHeader, size: 19).weight(.bold))
                .foregroundColor(T.text)
            Text("Nice work. Enjoy the rest of your day.")
                .font(.custom(T.fontBody, size: 14))
                .foregroundColor(T.textSec)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 20)
    }

    private var emptyTimeline: some View {
        VStack(spacing: 16) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 44))
                .foregroundColor(Cat.routine.solid)
            Text("No tasks yet")
                .font(.custom(T.fontHeader, size: 20).weight(.bold))
                .foregroundColor(T.text)
            Text("Tap + to add something,\nor let AI break it down.")
                .font(.custom(T.fontBody, size: 15))
                .foregroundColor(T.textSec)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - FAB

    private var fab: some View {
        Button {
            showingAddTask = true
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(T.primary)
                )
                .shadow(color: Color(hex: "#FF7A59").opacity(0.45), radius: 12, x: 0, y: 10)
        }
        .padding(.trailing, 22)
        .padding(.bottom, 20)
    }

    // MARK: - Sorting & grouping

    private func sortTasks(_ arr: [TaskBlock]) -> [TaskBlock] {
        switch sorting {
        case .time:
            return arr.sorted { ($0.startTime ?? .distantPast) < ($1.startTime ?? .distantPast) }
        case .alphabetical:
            return arr.sorted { ($0.title ?? "").localizedCaseInsensitiveCompare($1.title ?? "") == .orderedAscending }
        case .duration:
            return arr.sorted { $0.durationMinutes < $1.durationMinutes }
        }
    }

    private func groupedActive() -> [TaskGroupSection] {
        let sorted = sortTasks(activeTasks)
        switch grouping {
        case .none:
            return [TaskGroupSection(title: "", tasks: sorted)]
        case .priority:
            return [Int16(3), 2, 1, 0].compactMap { p in
                let items = sorted.filter { $0.priority == p }
                return items.isEmpty ? nil : TaskGroupSection(title: priorityGroupName(p), tasks: items)
            }
        case .duration:
            return (0...3).compactMap { b in
                let items = sorted.filter { durationBucket($0.durationMinutes) == b }
                return items.isEmpty ? nil : TaskGroupSection(title: durationGroupName(b), tasks: items)
            }
        case .eisenhower:
            let quadrants: [(String, (TaskBlock) -> Bool)] = [
                ("Do first · urgent & important", { isImportant($0) && isUrgent($0) }),
                ("Plan · important, not urgent", { isImportant($0) && !isUrgent($0) }),
                ("Delegate · urgent, not important", { !isImportant($0) && isUrgent($0) }),
                ("Later · neither", { !isImportant($0) && !isUrgent($0) })
            ]
            return quadrants.compactMap { name, pred in
                let items = sorted.filter(pred)
                return items.isEmpty ? nil : TaskGroupSection(title: name, tasks: items)
            }
        }
    }

    private func priorityGroupName(_ p: Int16) -> String {
        switch p {
        case 3: return "High priority"
        case 2: return "Medium priority"
        case 1: return "Low priority"
        default: return "No priority"
        }
    }

    private func durationBucket(_ m: Int32) -> Int {
        if m <= 15 { return 0 }
        if m <= 30 { return 1 }
        if m <= 60 { return 2 }
        return 3
    }

    private func durationGroupName(_ b: Int) -> String {
        switch b {
        case 0: return "Quick · under 15 min"
        case 1: return "Short · 15–30 min"
        case 2: return "Medium · 30–60 min"
        default: return "Long · 1 hour+"
        }
    }

    private func isImportant(_ t: TaskBlock) -> Bool { t.priority >= 2 }
    private func isUrgent(_ t: TaskBlock) -> Bool {
        guard let s = t.startTime else { return false }
        return s.timeIntervalSince(now) <= 2 * 3600   // starts within 2h or already overdue
    }

    private func toggleCompletion(_ task: TaskBlock) {
        withAnimation(.easeInOut(duration: 0.3)) {
            task.isCompleted.toggle()
            task.completedAt = task.isCompleted ? Date() : nil
        }
        if task.isCompleted {
            SoundPlayer.shared.playSuccess()
        }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
        try? viewContext.save()
    }
}

// MARK: - Timeline Row

struct TimelineRow: View {
    @ObservedObject var task: TaskBlock
    @Environment(\.managedObjectContext) private var viewContext
    let now: Date
    let isLast: Bool
    let onTap: () -> Void
    @State private var showEdit = false
    @State private var showMove = false
    @Environment(\.spawnConfetti) private var spawnConfetti

    private var taskEnd: Date {
        (task.startTime ?? now).addingTimeInterval(TimeInterval(task.durationMinutes) * 60)
    }
    private var isDone: Bool { task.isCompleted }
    private var isNow: Bool {
        guard !isDone, let s = task.startTime else { return false }
        return now >= s && now < taskEnd
    }
    private var progress: CGFloat {
        guard isNow, let s = task.startTime else { return 0 }
        let total = TimeInterval(task.durationMinutes) * 60
        return CGFloat(min(max(now.timeIntervalSince(s) / total, 0), 1))
    }
    private var cc: CatColors { Cat.named(task.category ?? "work") }
    private var remaining: Int {
        guard isNow, let s = task.startTime else { return 0 }
        let total = TimeInterval(task.durationMinutes) * 60
        return max(0, Int((total - now.timeIntervalSince(s)) / 60))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Time label
            Text(task.startTime?.formatted(.dateTime.hour().minute()) ?? "")
                .font(.custom(T.fontHeader, size: 13).weight(.bold))
                .foregroundColor(isDone ? T.textTer : T.textSec)
                .frame(width: 50, alignment: .trailing)
                .padding(.top, 12)

            // Card
            ZStack(alignment: .leading) {
                HStack(spacing: 12) {
                    // Tapping the card body opens the actions menu.
                    Menu {
                        taskMenu
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isNow ? T.surface : cc.bg)
                                    .frame(width: 40, height: 40)
                                Image(systemName: task.iconName ?? "circle")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(isDone ? T.textTer : cc.ink)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title ?? "Untitled")
                                    .font(.custom(T.fontHeader, size: 15).weight(.bold))
                                    .foregroundColor(isDone ? T.textTer : T.text)
                                    .strikethrough(isDone, color: T.textTer)
                                    .multilineTextAlignment(.leading)

                                HStack(spacing: 6) {
                                    Text(formatDuration(task.durationMinutes))
                                        .font(.custom(T.fontBody, size: 12).weight(.medium))
                                        .foregroundColor(T.textSec)
                                    if isNow {
                                        Circle()
                                            .fill(T.textTer)
                                            .frame(width: 3, height: 3)
                                        Text("\(remaining > 60 ? "\(remaining/60)h" : "\(remaining)m") left")
                                            .font(.custom(T.fontBody, size: 12).weight(.bold))
                                            .foregroundColor(cc.ink)
                                    }
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Explicit, obvious completion control — the one place to tap.
                    Button {
                        if !isDone {                       // celebrate on completion (always)
                            spawnConfetti(.zero)           // host bursts from screen centre
                        }
                        onTap()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(isDone ? T.secondary : Color.clear)
                            Circle()
                                .strokeBorder(isDone ? T.secondary : cc.solid, lineWidth: 2)
                            if isDone {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 26, height: 26)
                        .frame(width: 44, height: 44)   // generous tap target
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isDone ? "Mark not done" : "Mark done")
                }
                .padding(.vertical, 14)
                .padding(.leading, 14)
                .padding(.trailing, 4)
            }
            .background(
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isNow ? cc.bg : T.surface)
                    // "Now" progress fill — lives here so it's clipped to the card and never bleeds past the corners.
                    if isNow {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(cc.ink.opacity(0.12))
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    // Slim category accent on the left edge — replaces the old rail dots.
                    Rectangle()
                        .fill(isDone ? Color(lightHex: "#D8D2C5", darkHex: "#3A322B") : (isNow ? cc.ink : cc.solid))
                        .frame(width: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            )
            .shadow(
                color: isNow ? cc.bg : Color(red: 40/255, green: 30/255, blue: 20/255).opacity(0.05),
                radius: isNow ? 9 : 4,
                x: 0, y: isNow ? 6 : 2
            )
            .opacity(isDone ? 0.7 : 1)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
        .sheet(isPresented: $showEdit) {
            EditTaskSheet(task: task)
        }
        .sheet(isPresented: $showMove) {
            MoveTaskSheet(task: task)
        }
    }

    // MARK: - Task actions menu

    @ViewBuilder
    private var taskMenu: some View {
        Button { startTask() } label: { Label("Start task", systemImage: "play.circle") }
        Button { generateSteps() } label: { Label("Generate steps", systemImage: "wand.and.stars") }
        Button { showEdit = true } label: { Label("Edit task", systemImage: "square.and.pencil") }

        Section {
            Button { makeCopy() } label: { Label("Make a copy", systemImage: "doc.on.doc") }
            Button { showMove = true } label: { Label("Move", systemImage: "calendar") }
            if !Calendar.current.isDateInToday(task.startTime ?? Date()) {
                Button { moveToToday() } label: { Label("Move to today", systemImage: "arrow.uturn.forward") }
            }
        }

        Section {
            Button(role: .destructive) { deleteTask() } label: { Label("Delete task", systemImage: "trash") }
        }
    }

    private func startTask() {
        AppRouter.shared.focusRequest = FocusRequest(
            category: task.category ?? "work",
            minutes: Int(task.durationMinutes),
            title: task.title ?? ""
        )
        AppRouter.shared.selectedTab = .focus
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    private func makeCopy() {
        let copy = TaskBlock(context: viewContext)
        copy.id = UUID()
        copy.title = task.title
        copy.subtitle = task.subtitle
        copy.iconName = task.iconName
        copy.colorHex = task.colorHex
        copy.category = task.category
        copy.startTime = task.startTime
        copy.durationMinutes = task.durationMinutes
        copy.notes = task.notes
        copy.isCompleted = false
        copy.createdAt = Date()
        withAnimation { try? viewContext.save() }
    }

    private func moveToToday() {
        guard let s = task.startTime else { return }
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: s)
        if let newDate = cal.date(bySettingHour: c.hour ?? 9, minute: c.minute ?? 0, second: 0, of: Date()) {
            withAnimation { task.startTime = newDate }
            try? viewContext.save()
        }
    }

    private func deleteTask() {
        withAnimation { viewContext.delete(task) }
        try? viewContext.save()
    }

    /// Break this task into AI-generated micro-steps (replacing it), scheduled back-to-back.
    private func generateSteps() {
        let title = task.title ?? ""
        guard !title.isEmpty else { return }
        let ctx = viewContext
        let cat = task.category ?? "work"
        let startBase = task.startTime ?? Date()
        let original = task
        Task { @MainActor in
            let steps: [TaskBreakdown.Step]
            do { steps = try await ClaudeAPIClient().breakDown(task: title).steps }
            catch { steps = FallbackBreakdown.generate(for: title).steps }
            guard !steps.isEmpty else { return }
            var cursor = startBase
            for step in steps {
                let t = TaskBlock(context: ctx)
                t.id = UUID()
                t.title = step.title
                t.iconName = step.icon
                t.category = cat
                t.startTime = cursor
                t.durationMinutes = Int32(step.duration)
                t.createdAt = Date()
                cursor = cursor.addingTimeInterval(TimeInterval(step.duration) * 60)
            }
            ctx.delete(original)
            try? ctx.save()
        }
    }

    private func formatDuration(_ min: Int32) -> String {
        if min >= 60 {
            let h = min / 60
            let m = min % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(min)m"
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Today organize options

struct TaskGroupSection: Identifiable {
    var id: String { title }
    let title: String
    let tasks: [TaskBlock]
}

enum TodayGrouping: String, CaseIterable {
    case none, priority, duration, eisenhower

    var label: String {
        switch self {
        case .none: return "No grouping"
        case .priority: return "By priority"
        case .duration: return "By duration"
        case .eisenhower: return "Eisenhower matrix"
        }
    }
    var icon: String {
        switch self {
        case .none: return "rectangle.grid.1x2"
        case .priority: return "flag.fill"
        case .duration: return "clock.fill"
        case .eisenhower: return "square.grid.2x2.fill"
        }
    }
}

enum TodaySorting: String, CaseIterable {
    case time, alphabetical, duration

    var label: String {
        switch self {
        case .time: return "By time"
        case .alphabetical: return "Alphabetical"
        case .duration: return "By duration"
        }
    }
    var icon: String {
        switch self {
        case .time: return "clock"
        case .alphabetical: return "textformat.abc"
        case .duration: return "timer"
        }
    }
}

// MARK: - Confetti

/// A one-shot native confetti pop. Plays once when it appears, then settles invisible.
/// Re-create it (via `.id(...)`) to replay. No timers, no dependencies.
struct ConfettiBurst: View {
    private struct Piece: Identifiable {
        let id = UUID()
        let color: Color
        let dx: CGFloat
        let dy: CGFloat
        let size: CGFloat
        let spin: Double
        let isCircle: Bool
    }

    @State private var fired = false
    private let pieces: [Piece]

    init(count: Int = 20) {
        let palette: [Color] = [
            T.primary, T.secondary,
            Color(hex: "#F0B450"), Color(hex: "#8E78D0"), Color(hex: "#7FA7E6")
        ]
        pieces = (0..<count).map { _ in
            let angle = Double.random(in: (-Double.pi * 0.92)...(-Double.pi * 0.08))  // fan upward
            let dist = CGFloat.random(in: 60...150)
            return Piece(
                color: palette.randomElement() ?? T.primary,
                dx: CGFloat(cos(angle)) * dist,
                dy: CGFloat(sin(angle)) * dist,     // negative == up
                size: CGFloat.random(in: 8...14),
                spin: Double.random(in: -260...260),
                isCircle: Bool.random()
            )
        }
    }

    var body: some View {
        ZStack {
            ForEach(pieces) { p in
                Group {
                    if p.isCircle {
                        Circle().fill(p.color).frame(width: p.size, height: p.size)
                    } else {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(p.color)
                            .frame(width: p.size, height: p.size * 0.6)
                    }
                }
                .rotationEffect(.degrees(fired ? p.spin : 0))
                .offset(x: fired ? p.dx : 0, y: fired ? p.dy + 28 : 0)  // pop up & out, slight fall
                .opacity(fired ? 0 : 1)
                .scaleEffect(fired ? 0.6 : 1)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) { fired = true }
        }
    }
}

// MARK: - Screen-level confetti host

/// Lets any descendant (e.g. a TimelineRow) fire confetti at a screen-space point.
/// Rendered at the screen level so it survives the row being removed/collapsed.
private struct SpawnConfettiKey: EnvironmentKey {
    static let defaultValue: (CGPoint) -> Void = { _ in }
}

extension EnvironmentValues {
    var spawnConfetti: (CGPoint) -> Void {
        get { self[SpawnConfettiKey.self] }
        set { self[SpawnConfettiKey.self] = newValue }
    }
}

struct ConfettiItem: Identifiable {
    let id = UUID()
    let point: CGPoint
}

struct ConfettiHost: ViewModifier {
    @State private var items: [ConfettiItem] = []
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .environment(\.spawnConfetti, spawn)
            .coordinateSpace(.named("tempaRoot"))
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { size = geo.size }
                        .onChange(of: geo.size) { _, s in size = s }
                }
            )
            .overlay {
                ZStack {
                    ForEach(items) { item in
                        ConfettiBurst().position(item.point)
                    }
                }
                .allowsHitTesting(false)
            }
    }

    private func spawn(_ point: CGPoint) {
        // Always show confetti — if we didn't get a valid anchor, burst from the
        // upper-centre of the screen so it's never invisible.
        let valid = point != .zero && point.x.isFinite && point.y.isFinite
        let p = valid ? point : CGPoint(x: size.width / 2, y: max(140, size.height * 0.3))
        let item = ConfettiItem(point: p)
        items.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            items.removeAll { $0.id == item.id }
        }
    }
}

extension View {
    func confettiHost() -> some View { modifier(ConfettiHost()) }
}

#Preview {
    TodayView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
