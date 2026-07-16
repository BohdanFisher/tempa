import SwiftUI
import CoreData
import Combine

/// Replaces the old "Now" tab. A compact, swipeable one-week strip (swipe to move
/// week-by-week) + the selected day's tasks. When today is selected, the old "Now"
/// spotlight (current task + what's next) is surfaced right here — no separate tab.
struct CalendarView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // Personal planner → small dataset, so we fetch everything and filter per day in memory.
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\TaskBlock.startTime, order: .forward)],
        animation: .default
    ) private var allTasks: FetchedResults<TaskBlock>

    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var weekOffset = 0          // 0 == current week
    @State private var now = Date()
    @State private var flatList = false
    @State private var slideEdge: Edge = .trailing   // day-switch slide direction
    @Namespace private var dayNS        // false = grouped (morning/day/evening), true = one flat list
    @State private var showDoneDay = false     // collapsible "Done" section for completed tasks

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private let cal = Calendar.current
    private let weekRange = -26...26           // ±6 months of swipeable weeks

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    weekStrip
                    // The day's list slides in from the direction you navigated.
                    dayTasksSection
                        .id(selectedDate)
                        .transition(.push(from: slideEdge))
                }
                .padding(.bottom, 140)
            }
        }
        .confettiHost()
        .onReceive(timer) { _ in now = Date() }
        .onChange(of: weekOffset) { old, new in
            // Only react to an actual swipe: if the selected day already lives in the
            // newly visible week (e.g. the "Today" button just set both), do nothing.
            // Otherwise keep the same weekday selected so the list tracks the visible week.
            let visible = weekDays(offset: new)
            guard !visible.contains(where: { cal.isDate($0, inSameDayAs: selectedDate) }) else { return }
            if let shifted = cal.date(byAdding: .weekOfYear, value: new - old, to: selectedDate) {
                slideEdge = new > old ? .trailing : .leading
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { selectedDate = cal.startOfDay(for: shifted) }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(monthTitle.uppercased())
                    .font(.custom(T.fontHeader, size: 13).weight(.semibold))
                    .tracking(0.5)
                    .foregroundColor(T.textSec)
                Text(selectedTitle)
                    .font(.custom(T.fontHeader, size: 30).weight(.heavy))
                    .tracking(-0.6)
                    .foregroundColor(T.text)
            }

            Spacer()

            if !cal.isDateInToday(selectedDate) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedDate = cal.startOfDay(for: Date())
                        weekOffset = 0
                    }
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                } label: {
                    Text("Today")
                        .font(.custom(T.fontHeader, size: 13).weight(.bold))
                        .foregroundColor(T.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(T.primary.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    // MARK: - Swipeable week strip

    private var weekStrip: some View {
        let marked = daysWithTasks   // compute once, not per chip
        return TabView(selection: $weekOffset) {
            ForEach(weekRange, id: \.self) { offset in
                HStack(spacing: 6) {
                    ForEach(weekDays(offset: offset), id: \.self) { day in
                        dayChip(day, marked: marked)
                    }
                }
                .padding(.horizontal, 20)
                .frame(maxHeight: .infinity, alignment: .top)
                .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 80)
    }

    private func dayChip(_ day: Date, marked: Set<Date>) -> some View {
        let isSelected = cal.isDate(day, inSameDayAs: selectedDate)
        let isToday = cal.isDateInToday(day)
        let hasTasks = marked.contains(day)

        return Button {
            slideEdge = day >= selectedDate ? .trailing : .leading
            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { selectedDate = day }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            VStack(spacing: 3) {
                Text(weekdayLetter(day))
                    .font(.custom(T.fontHeader, size: 11).weight(.bold))
                    .foregroundColor(isSelected ? Color.white.opacity(0.9) : T.textTer)
                Text("\(cal.component(.day, from: day))")
                    .font(.custom(T.fontHeader, size: 16).weight(.heavy))
                    .foregroundColor(isSelected ? .white : (isToday ? T.primary : T.text))
                Circle()
                    .fill(hasTasks ? (isSelected ? Color.white : T.primary) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                // The coral fill glides from day to day instead of teleporting.
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(T.primary)
                        .matchedGeometryEffect(id: "daySel", in: dayNS)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(T.primary.opacity(0.10))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Day tasks

    private var dayTasksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(dayHeading)
                    .font(.custom(T.fontHeader, size: 12).weight(.heavy))
                    .tracking(1.5)
                    .foregroundColor(T.textSec)
                Spacer()
                if !dayTasks.isEmpty { modeToggle }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 10)

            if dayTasks.isEmpty {
                emptyDay
            } else {
                if flatList {
                    flatTaskList
                } else {
                    groupedTaskList
                }
                if !doneDayTasks.isEmpty {
                    doneDaySection
                }
            }
        }
        // Pinch out (zoom in) → one flat list; pinch in (zoom out) → grouped by time of day.
        .gesture(
            MagnifyGesture()
                .onEnded { value in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if value.magnification > 1.15 { flatList = true }
                        else if value.magnification < 0.9 { flatList = false }
                    }
                }
        )
    }

    private var modeToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { flatList.toggle() }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            HStack(spacing: 4) {
                Image(systemName: flatList ? "square.grid.2x2" : "list.bullet")
                    .font(.system(size: 10, weight: .bold))
                Text(flatList ? "Grouped" : "All")
                    .font(.custom(T.fontHeader, size: 11).weight(.bold))
            }
            .foregroundColor(T.textSec)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(T.bgWarm))
        }
        .buttonStyle(.plain)
    }

    private var flatTaskList: some View {
        VStack(spacing: 0) {
            ForEach(activeDayTasks) { task in
                TimelineRow(task: task, now: now, isLast: task == activeDayTasks.last) {
                    toggleCompletion(task)
                }
            }
        }
        .padding(.top, 4)
    }

    private var doneDaySection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showDoneDay.toggle() }
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(T.secondary)
                    Text("Done · \(doneDayTasks.count)")
                        .font(.custom(T.fontHeader, size: 14).weight(.bold))
                        .foregroundColor(T.textSec)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(T.textTer)
                        .rotationEffect(.degrees(showDoneDay ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.surface))
                .tempaShadowSm()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if showDoneDay {
                VStack(spacing: 0) {
                    ForEach(doneDayTasks) { task in
                        TimelineRow(task: task, now: now, isLast: task == doneDayTasks.last) {
                            toggleCompletion(task)
                        }
                    }
                }
                .padding(.top, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var groupedTaskList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groupedDayTasks, id: \.part) { group in
                HStack(spacing: 8) {
                    Image(systemName: group.part.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(group.part.tint)
                    Text(group.part.label)
                        .font(.custom(T.fontHeader, size: 12).weight(.heavy))
                        .tracking(1.5)
                        .foregroundColor(T.textSec)
                    Spacer()
                    Text("\(group.tasks.count)")
                        .font(.custom(T.fontBody, size: 12).weight(.medium))
                        .foregroundColor(T.textTer)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 6)

                ForEach(group.tasks) { task in
                    TimelineRow(task: task, now: now, isLast: task == group.tasks.last) {
                        toggleCompletion(task)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private var activeDayTasks: [TaskBlock] { dayTasks.filter { !$0.isCompleted } }
    private var doneDayTasks: [TaskBlock] { dayTasks.filter(\.isCompleted) }

    /// Active day tasks bucketed into morning / afternoon / evening (empty buckets dropped).
    private var groupedDayTasks: [(part: DayPart, tasks: [TaskBlock])] {
        let buckets = Dictionary(grouping: activeDayTasks) { task in
            DayPart.of(task.startTime ?? selectedDate, cal)
        }
        return DayPart.allCases.compactMap { part in
            guard let tasks = buckets[part], !tasks.isEmpty else { return nil }
            return (part, tasks)
        }
    }

    private enum DayPart: Int, CaseIterable, Hashable {
        case morning, afternoon, evening

        static func of(_ date: Date, _ cal: Calendar) -> DayPart {
            let h = cal.component(.hour, from: date)
            if h < 12 { return .morning }
            if h < 17 { return .afternoon }
            return .evening
        }

        var label: String {
            switch self {
            case .morning: return String(localized: "MORNING")
            case .afternoon: return String(localized: "AFTERNOON")
            case .evening: return String(localized: "EVENING")
            }
        }

        var icon: String {
            switch self {
            case .morning: return "sunrise.fill"
            case .afternoon: return "sun.max.fill"
            case .evening: return "moon.stars.fill"
            }
        }

        var tint: Color {
            switch self {
            case .morning: return Color(hex: "#F0B450")
            case .afternoon: return T.primary
            case .evening: return Color(hex: "#8E78D0")
            }
        }
    }

    private var emptyDay: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 34))
                .foregroundColor(T.textTer)
            Text("Nothing scheduled")
                .font(.custom(T.fontHeader, size: 16).weight(.bold))
                .foregroundColor(T.text)
            Text("Swipe to another week, or add a task from Today.")
                .font(.custom(T.fontBody, size: 13))
                .foregroundColor(T.textSec)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
    }

    // MARK: - Data helpers

    private var dayTasks: [TaskBlock] {
        allTasks.filter { t in
            guard let s = t.startTime else { return false }
            return cal.isDate(s, inSameDayAs: selectedDate)
        }
    }

    private var daysWithTasks: Set<Date> {
        Set(allTasks.compactMap { $0.startTime.map { cal.startOfDay(for: $0) } })
    }

    private func weekDays(offset: Int) -> [Date] {
        let base = cal.dateInterval(of: .weekOfYear, for: Date())?.start
            ?? cal.startOfDay(for: Date())
        let weekStart = cal.date(byAdding: .weekOfYear, value: offset, to: base) ?? base
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
            .map { cal.startOfDay(for: $0) }
    }

    private func weekdayLetter(_ day: Date) -> String {
        let f = DateFormatter()
        let symbols = f.veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let idx = cal.component(.weekday, from: day) - 1
        return symbols[idx]
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yMMMM")
        return f.string(from: selectedDate)
    }

    private var selectedTitle: String {
        if cal.isDateInToday(selectedDate) { return String(localized: "Today") }
        if cal.isDateInTomorrow(selectedDate) { return String(localized: "Tomorrow") }
        if cal.isDateInYesterday(selectedDate) { return String(localized: "Yesterday") }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return f.string(from: selectedDate)
    }

    private var dayHeading: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return f.string(from: selectedDate).uppercased()
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

#Preview {
    CalendarView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
