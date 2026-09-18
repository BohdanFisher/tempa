import SwiftUI
import CoreData
import Combine

struct TodayView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SettingsStore.self) private var settings
    @Environment(SubscriptionManager.self) private var subs

    @FetchRequest private var tasks: FetchedResults<TaskBlock>
    @State private var router = AppRouter.shared
    @State private var showingAddTask = false
    @State private var now = Date()
    @State private var dayStart = Calendar.current.startOfDay(for: Date())
    @Environment(\.scenePhase) private var scenePhase
    @State private var showCompleted = false
    @AppStorage("todayGrouping") private var grouping: TodayGrouping = .none
    @AppStorage("todaySorting") private var sorting: TodaySorting = .time
    /// The one-time "set up from your answers" card after the first purchase.
    @AppStorage(FirstDayStash.receiptKey) private var showFirstDayReceipt = false
    /// Until the user has added a task of their own, the "+" wears a label —
    /// the door people didn't notice gets a name.
    @State private var hasOwnTask = true

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init() {
        _tasks = FetchRequest(
            sortDescriptors: [SortDescriptor(\TaskBlock.startTime, order: .forward)],
            predicate: Self.dayPredicate(from: Calendar.current.startOfDay(for: Date())),
            animation: .default
        )
    }

    private static func dayPredicate(from start: Date) -> NSPredicate {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return NSPredicate(format: "startTime >= %@ AND startTime < %@", start as NSDate, end as NSDate)
    }

    /// The fetch window is baked at init — roll it forward once a new day
    /// starts, or the screen keeps living in yesterday after midnight.
    private func refreshDayWindowIfNeeded() {
        let today = Calendar.current.startOfDay(for: now)
        guard today != dayStart else { return }
        dayStart = today
        tasks.nsPredicate = Self.dayPredicate(from: today)
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

    /// One thing at a time: the block running now; else the next one coming
    /// up; else the earliest one whose time has passed, offered without a
    /// clock ("whenever you're ready") — a day never opens on a bare list.
    /// The hero is not a banner of its own: it is a ROW of the timeline (the
    /// first one, unless the user groups their day), in the same time gutter
    /// and card column as every other row, only taller, tinted, and carrying
    /// the one Start button on the screen.
    enum HeroMode { case now, next, waiting }
    private var hero: (TaskBlock, HeroMode)? {
        if let current = currentTask { return (current, .now) }
        if let next = activeTasks.first(where: { ($0.startTime ?? .distantPast) > now }) { return (next, .next) }
        if let waiting = activeTasks.first(where: { ($0.startTime ?? .distantFuture) <= now }) { return (waiting, .waiting) }
        return nil
    }
    private var dateString: String {
        let f = DateFormatter()
        f.locale = AppLanguage.current.locale
        f.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return f.string(from: now)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            T.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    greetingSection
                    if showFirstDayReceipt {
                        firstDayReceipt
                            .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
                    }
                    dayPulseCard
                    timelineSection
                }
                .padding(.bottom, 140)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: hero?.0.objectID)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: showFirstDayReceipt)
            }

            fab
        }
        .confettiHost()
        .onReceive(timer) { _ in
            now = Date()
            refreshDayWindowIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                now = Date()
                refreshDayWindowIfNeeded()
            }
        }
        .onAppear { refreshOwnTaskFlag() }
        .fullScreenCover(isPresented: $showingAddTask, onDismiss: { refreshOwnTaskFlag() }) {
            AddTaskSheet()
        }
        .onChange(of: router.addTaskRequest) { _, req in
            // e.g. Welcome Back's "Plan something small" → open the add-task sheet.
            guard req != nil else { return }
            router.addTaskRequest = nil   // consume
            showingAddTask = true
        }
    }

    // MARK: - First-day receipt

    /// Shown once, right after the first purchase: the "Creating your calm
    /// day…" checklist from the funnel, now with the real values behind it
    /// — and the trial's end date said plainly, so nobody cancels out of
    /// fear of forgetting.
    private var firstDayReceipt: some View {
        let name = UserDefaults.standard.string(forKey: "userName")?.trimmingCharacters(in: .whitespaces) ?? ""
        let time = Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguage.current.locale)
        let day = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(AppLanguage.current.locale)
        return VStack(alignment: .leading, spacing: 14) {
            Group {
                if name.isEmpty {
                    Text("Your day is set up from your answers.")
                } else {
                    Text("\(name), your day is set up from your answers.")
                }
            }
            .font(.custom(T.fontHeader, size: 18).weight(.heavy))
            .tracking(-0.3)
            .foregroundColor(T.text)
            .lineSpacing(2)

            VStack(alignment: .leading, spacing: 10) {
                receiptRow("sunrise.fill", Text("Wake time · \(settings.wakeTime.formatted(time))"))
                if let dip = settings.energyDipTime {
                    receiptRow("leaf.fill", Text("Energy dip · \(dip.formatted(time)) — that block stays light"))
                }
                receiptRow("checklist", Text("Meals, a breather and five minutes to plan tomorrow are already on your day. Move or delete any of them."))
                if let ends = subs.trialEndsAt {
                    receiptRow("lock.open.fill", Text("Free until \(ends.formatted(day)) · nothing is charged before then · cancel any time in Settings"))
                }
            }

            TempaButton(label: "Got it", variant: .ghost, size: .sm) {
                showFirstDayReceipt = false
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(T.surface)
        )
        .tempaShadowSm()
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private func receiptRow(_ icon: String, _ text: Text) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(T.secondaryDeep)
                .frame(width: 22, height: 22)
            text
                .font(.custom(T.fontBody, size: 14).weight(.medium))
                .foregroundColor(T.text)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// True once any task exists that onboarding didn't seed.
    private func refreshOwnTaskFlag() {
        let req = NSFetchRequest<TaskBlock>(entityName: "TaskBlock")
        req.predicate = NSPredicate(format: "notes == nil OR NOT (notes BEGINSWITH %@)", DayBuilder.autoNote)
        req.fetchLimit = 1
        hasOwnTask = ((try? viewContext.count(for: req)) ?? 0) > 0
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
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: activeTasks.count)
        .padding(.top, 4)
    }

    /// What the ungrouped feed is made of. ONE ForEach over these keeps a
    /// row's identity wherever it lands — promoted to hero, or slipping past
    /// its time — so an open edit sheet never jumps to another task or
    /// closes under the user's fingers.
    private enum FeedItem: Identifiable {
        case task(TaskBlock, HeroMode?)
        case wheneverHeader(Int)
        var id: AnyHashable {
            switch self {
            case .task(let task, _): return task.objectID
            case .wheneverHeader: return "whenever-header"
            }
        }
    }

    /// Hero first, always. Sorted by time, the rest stays a real timeline:
    /// what's still ahead in clock order, then the blocks whose time has
    /// passed, gathered under "whenever you're ready" — below, not on top,
    /// so an unticked breakfast is neither the first thing on the screen nor
    /// a 08:00 sitting under a 14:00. Any other sort is the user's own order.
    private func feedItems() -> [FeedItem] {
        let pinned = hero
        let rest = activeTasks.filter { $0 != pinned?.0 }
        var items: [FeedItem] = []
        if let (task, mode) = pinned { items.append(.task(task, mode)) }
        guard sorting == .time, let mode = pinned?.1, mode != .waiting else {
            // .waiting: everything left is past its time and the hero is the
            // earliest of it — its own label already says "whenever".
            return items + sortTasks(rest).map { .task($0, nil) }
        }
        let passed = rest.filter { task in
            guard let start = task.startTime else { return false }
            return start.addingTimeInterval(TimeInterval(task.durationMinutes) * 60) <= now
        }
        let ahead = rest.filter { !passed.contains($0) }
        items += sortTasks(ahead).map { .task($0, nil) }
        if !passed.isEmpty {
            items.append(.wheneverHeader(passed.count))
            items += sortTasks(passed).map { .task($0, nil) }
        }
        return items
    }

    @ViewBuilder
    private var activeContent: some View {
        if grouping == .none {
            ForEach(feedItems()) { item in
                switch item {
                case .task(let task, let mode):
                    TimelineRow(task: task, now: now, isLast: false, hero: mode) {
                        toggleCompletion(task)
                    }
                    .transition(rowTransition)
                case .wheneverHeader(let count):
                    groupHeader(String(localized: "WHENEVER YOU'RE READY", bundle: .appLanguage), count)
                        .transition(.opacity)
                }
            }
        } else {
            // Grouped is the user's own arrangement: the hero is lit where
            // their grouping puts it, not pulled out of its group.
            let pinned = hero
            ForEach(groupedActive()) { group in
                groupHeader(group.title, group.tasks.count)
                ForEach(group.tasks) { task in
                    TimelineRow(task: task, now: now, isLast: task == group.tasks.last,
                                hero: task == pinned?.0 ? pinned?.1 : nil) {
                        toggleCompletion(task)
                    }
                    .transition(rowTransition)
                }
            }
        }
    }

    /// New rows glide up from below; leaving rows melt away in place.
    private var rowTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .scale(scale: 0.97).combined(with: .opacity)
        )
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
                .onAppear { AnalyticsService.shared.track(.dayComplete) }
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
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    // Quarter-turn into a "×" while the add sheet is up.
                    .rotationEffect(.degrees(showingAddTask ? 45 : 0))
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: showingAddTask)
                if !hasOwnTask {
                    Text("Add one small thing")
                        .font(.custom("Nunito-ExtraBold", size: 16))
                        .foregroundColor(.white)
                        .padding(.trailing, 6)
                }
            }
            .frame(minWidth: 60, minHeight: 60)
            .padding(.horizontal, hasOwnTask ? 0 : 14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(T.primary)
            )
            .shadow(color: Color(hex: "#FF7A59").opacity(0.45), radius: 12, x: 0, y: 10)
        }
        .buttonStyle(SpringPressStyle(scale: 0.88))
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
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            task.isCompleted.toggle()
            task.completedAt = task.isCompleted ? Date() : nil
        }
        if task.isCompleted {
            SoundPlayer.shared.playSuccess()
            AnalyticsService.shared.track(.taskCompleted)
        }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
        try? viewContext.save()
    }
}

// MARK: - Timeline Row

struct TimelineRow: View {
    @Environment(SubscriptionManager.self) private var subs
    @State private var showProPaywall = false    // AI features are Pro
    @ObservedObject var task: TaskBlock
    @Environment(\.managedObjectContext) private var viewContext
    let now: Date
    let isLast: Bool
    /// Non-nil for the ONE row that opens the day: same gutter, same card
    /// column, same check circle — taller, tinted, labelled, with Start.
    var hero: TodayView.HeroMode? = nil
    let onTap: () -> Void
    @State private var showEdit = false
    @State private var showMove = false
    @State private var isGeneratingSteps = false
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
    private var isHero: Bool { hero != nil }
    /// The running block and the hero share one look: tinted, inked, lifted.
    private var isLit: Bool { isNow || isHero }
    private var remaining: Int {
        guard isNow, let s = task.startTime else { return 0 }
        let total = TimeInterval(task.durationMinutes) * 60
        return max(0, Int((total - now.timeIntervalSince(s)) / 60))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Time label. "Whenever you're ready" has no clock on purpose — a
            // start time that's hours gone would read as a reproach.
            Text(hero == .waiting ? "" : (task.startTime?.formatted(.dateTime.hour().minute()) ?? ""))
                .font(.custom(T.fontHeader, size: 13).weight(.bold))
                .foregroundColor(isDone ? T.textTer : (isHero ? cc.ink : T.textSec))
                .frame(width: 50, alignment: .trailing)
                .padding(.top, 12)

            // Card
            ZStack(alignment: .leading) {
              VStack(alignment: .leading, spacing: 0) {
                if let hero {
                    heroEyebrow(hero)
                        .padding(.bottom, 10)
                        .padding(.trailing, 10)
                }
                HStack(spacing: 12) {
                    // Tapping the card body opens the actions menu.
                    Menu {
                        taskMenu
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isLit ? T.surface : cc.bg)
                                    .frame(width: 40, height: 40)
                                if isGeneratingSteps {
                                    ProgressView().tint(cc.ink)
                                } else {
                                    Image(systemName: task.iconName ?? "circle")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(isDone ? T.textTer : cc.ink)
                                }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title ?? String(localized: "Untitled", bundle: .appLanguage))
                                    .font(.custom(T.fontHeader, size: isHero ? 20 : 15).weight(isHero ? .heavy : .bold))
                                    .tracking(isHero ? -0.3 : 0)
                                    // The hero's column is narrow for 20pt: shrink a
                                    // long word a little before ever breaking it.
                                    .lineLimit(isHero ? 3 : nil)
                                    .minimumScaleFactor(isHero ? 0.8 : 1)
                                    .foregroundColor(isDone ? T.textTer : T.text)
                                    .strikethrough(isDone, color: T.textTer)
                                    .multilineTextAlignment(.leading)

                                HStack(spacing: 6) {
                                    Text(formatDuration(task.durationMinutes))
                                        .font(.custom(T.fontBody, size: isHero ? 13 : 12).weight(.medium))
                                        .foregroundColor(isHero ? cc.ink : T.textSec)
                                    if isNow {
                                        Circle()
                                            .fill(T.textTer)
                                            .frame(width: 3, height: 3)
                                        Group {
                                            if remaining >= 60 && remaining % 60 != 0 {
                                                Text("\(remaining / 60) h \(remaining % 60) min left")
                                            } else if remaining >= 60 {
                                                Text("\(remaining / 60) h left")
                                            } else {
                                                Text("\(remaining) min left")
                                            }
                                        }
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
                                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                            }
                        }
                        .scaleEffect(isDone ? 1.06 : 1.0)
                        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: isDone)
                        .frame(width: 26, height: 26)
                        .frame(width: 44, height: 44)   // generous tap target
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SpringPressStyle(scale: 0.85))
                    .accessibilityLabel(isDone ? "Mark not done" : "Mark done")
                }
                if isHero {
                    // One tap → the hourglass is already running, sized to
                    // THIS block. The Focus tab clamps to 5–60 min, so the
                    // label says what it will actually set. Full width: one
                    // button can't be misaligned, and long words just fit.
                    TempaButton(label: "Start · \(max(5, min(60, Int(task.durationMinutes)))) min",
                                variant: .primary, size: .md, fullWidth: true) {
                        startTask(source: "hero", haptic: false)   // the button has its own
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 10)   // the card's trailing inset is 4 (for the 44pt check target)
                }
              }
              .padding(.vertical, 14)
              .padding(.leading, 14)
              .padding(.trailing, 4)
            }
            .background(
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isLit ? cc.bg : T.surface)
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
                        .fill(isDone ? Color(lightHex: "#D8D2C5", darkHex: "#3A322B") : (isLit ? cc.ink : cc.solid))
                        .frame(width: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            )
            .shadow(
                color: isLit ? cc.bg : Color(red: 40/255, green: 30/255, blue: 20/255).opacity(0.05),
                radius: isLit ? 9 : 4,
                x: 0, y: isLit ? 6 : 2
            )
            .opacity(isDone ? 0.7 : 1)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
        .fullScreenCover(isPresented: $showProPaywall) {
            // The user asked for steps and then paid — deliver the steps.
            PaywallView(allowDismiss: true) { generateSteps() }
        }
        .sheet(isPresented: $showEdit) {
            EditTaskSheet(task: task)
        }
        .sheet(isPresented: $showMove) {
            MoveTaskSheet(task: task)
        }
    }

    // MARK: - Hero label

    private func heroEyebrow(_ mode: TodayView.HeroMode) -> some View {
        HStack(spacing: 8) {
            if mode == .now {
                PulseDot(size: 8, color: cc.ink, rings: 2, speed: 3)
            }
            Group {
                switch mode {
                case .now: Text("RIGHT NOW")
                case .next: Text("UP NEXT")
                case .waiting: Text("WHENEVER YOU'RE READY")
                }
            }
            .font(.custom(T.fontHeader, size: 11).weight(.heavy))
            .tracking(2)
            .foregroundColor(cc.ink)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Task actions menu

    @ViewBuilder
    private var taskMenu: some View {
        Button { startTask(source: "task_row") } label: { Label("Start task", systemImage: "play.circle") }
        Button {
            if subs.isPro { generateSteps() } else { showProPaywall = true }
        } label: { Label("Generate steps", systemImage: "wand.and.stars") }
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

    private func startTask(source: String, haptic: Bool = true) {
        AnalyticsService.shared.track(.taskStarted, properties: ["source": source])
        AppRouter.shared.focusRequest = FocusRequest(
            category: task.category ?? "work",
            minutes: Int(task.durationMinutes),
            title: task.title ?? ""
        )
        AppRouter.shared.selectedTab = .focus
        #if os(iOS)
        if haptic { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
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
        copy.priority = task.priority
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
        // The await below takes seconds — a second tap must not spawn a second
        // set of steps (and delete the original twice). The guard is a shared
        // set keyed by the task, so it survives the row being re-created
        // (completing the task, regrouping) mid-flight.
        let guardID = task.objectID
        guard !title.isEmpty, !StepGenerationGuard.inFlight.contains(guardID) else { return }
        StepGenerationGuard.inFlight.insert(guardID)
        isGeneratingSteps = true
        let ctx = viewContext
        let cat = task.category ?? "work"
        let startBase = task.startTime ?? Date()
        let original = task
        Task { @MainActor in
            defer {
                StepGenerationGuard.inFlight.remove(guardID)
                isGeneratingSteps = false
            }
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
        case .none: return String(localized: "No grouping", bundle: .appLanguage)
        case .priority: return String(localized: "By priority", bundle: .appLanguage)
        case .duration: return String(localized: "By duration", bundle: .appLanguage)
        case .eisenhower: return String(localized: "Eisenhower matrix", bundle: .appLanguage)
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
        case .time: return String(localized: "By time", bundle: .appLanguage)
        case .alphabetical: return String(localized: "Alphabetical", bundle: .appLanguage)
        case .duration: return String(localized: "By duration", bundle: .appLanguage)
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

/// Tasks whose step-generation request is currently in flight — global so the
/// guard survives SwiftUI recreating the row mid-request.
@MainActor
enum StepGenerationGuard {
    static var inFlight = Set<NSManagedObjectID>()
}
