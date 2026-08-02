import SwiftUI
import CoreData
import Combine

/// "Me" — real usage stats: the day's energy battery (time vs planned load),
/// completion stats for today / week / month, where the time goes by category,
/// and the day streak. Everything is computed from Core Data, nothing is faked.
struct MeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SettingsStore.self) private var settings

    @State private var period: StatsPeriod = .today
    @State private var battery: StatsEngine.DayBattery?
    @State private var stats: StatsEngine.PeriodStats?
    @State private var cats: [StatsEngine.CategoryStat] = []
    @State private var streak: StatsEngine.StreakInfo?
    @State private var hourly: StatsEngine.HourlyActivity?
    @State private var focusDays: [StatsEngine.FocusDay] = []
    @State private var chartsShown = false     // bars grow in with a stagger
    @State private var shownPercent = 0        // battery % counts up
    @Namespace private var pickerNS

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    // Did-save notifications post on the SAVING context's thread (CloudKit imports
    // save on background queues) — debounce coalesces sync bursts AND hops to main,
    // so recompute() only ever touches viewContext/@State on the main thread.
    private let saveNotif = NotificationCenter.default
        .publisher(for: .NSManagedObjectContextDidSave)
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)

    enum StatsPeriod: String, CaseIterable {
        case today = "Today", week = "Week", month = "Month"
        var label: String {
            switch self {
            case .today: String(localized: "Today", bundle: .appLanguage)
            case .week: String(localized: "Week", bundle: .appLanguage)
            case .month: String(localized: "Month", bundle: .appLanguage)
            }
        }
        var daysBack: Int {
            switch self {
            case .today: 1
            case .week: 7
            case .month: 30
            }
        }
    }

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Me")
                        .font(.custom(T.fontHeader, size: 32).weight(.heavy))
                        .tracking(-0.5)
                        .foregroundColor(T.text)
                        .padding(.top, 20)

                    if let battery {
                        batteryCard(battery)
                    }

                    periodPicker
                        .padding(.top, 8)

                    if let stats {
                        statTiles(stats)
                        if period != .today {
                            chartCard(stats)
                        }
                    }

                    if let hourly {
                        heatmapCard(hourly)
                    }

                    focusCard

                    if !cats.isEmpty {
                        categoryCard
                    }

                    if let streak {
                        streakCard(streak)
                    }

                    Spacer(minLength: 90)
                }
                .padding(.horizontal, 20)
            }
        }
        .onAppear {
            recompute()
            chartsShown = true
        }
        .onChange(of: period) { _, _ in
            // Re-run the grow-in when the period flips.
            chartsShown = false
            recompute()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { chartsShown = true }
        }
        .onChange(of: battery?.percent, initial: true) { _, newValue in
            withAnimation(.spring(response: 0.9, dampingFraction: 0.9)) {
                shownPercent = newValue ?? 0
            }
        }
        .onReceive(timer) { _ in recompute() }
        .onReceive(saveNotif) { _ in recompute() }
    }

    private func recompute() {
        battery = StatsEngine.dayBattery(wakeTime: settings.wakeTime, context: viewContext)
        stats = StatsEngine.periodStats(daysBack: period.daysBack, context: viewContext)
        cats = StatsEngine.categoryStats(daysBack: period.daysBack, context: viewContext)
        streak = StatsEngine.streak(context: viewContext)
        hourly = StatsEngine.hourlyActivity(weeksBack: 4, context: viewContext)
        focusDays = StatsEngine.focusPerDay(daysBack: period.daysBack, context: viewContext)
    }

    // MARK: - Day battery

    private func batteryCard(_ b: StatsEngine.DayBattery) -> some View {
        let overbooked = b.freeMin < 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("DAY BATTERY")
                    .font(.custom(T.fontHeader, size: 12).weight(.heavy))
                    .tracking(1.2)
                    .foregroundColor(T.textSec)
                Spacer()
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(T.warning)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(shownPercent)%")
                    .font(.custom(T.fontHeader, size: 44).weight(.heavy))
                    .tracking(-1)
                    .foregroundColor(T.text)
                    .contentTransition(.numericText(value: Double(shownPercent)))
                Text("of your day left")
                    .font(.custom(T.fontBody, size: 14).weight(.medium))
                    .foregroundColor(T.textSec)
            }

            // Charge bar: what's left of the day, split into free vs planned.
            GeometryReader { geo in
                let w = geo.size.width
                let remainingW = w * b.remainingFrac
                let freeW = remainingW * b.freeFracOfRemaining
                ZStack(alignment: .leading) {
                    Capsule().fill(T.bgWarm)
                    HStack(spacing: 0) {
                        Rectangle().fill(T.secondary)
                            .frame(width: freeW)
                        Rectangle().fill(T.warning)
                            .frame(width: max(0, remainingW - freeW))
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 18)

            HStack(spacing: 14) {
                legendDot(color: T.secondary, text: String(localized: "\(hm(max(0, b.freeMin))) free", bundle: .appLanguage))
                legendDot(color: T.warning, text: String(localized: "\(hm(b.reservedMin)) planned", bundle: .appLanguage))
                Spacer()
                Text("\(hm(b.remainingMin)) left")
                    .font(.custom(T.fontHeader, size: 12).weight(.bold))
                    .foregroundColor(T.textSec)
            }

            if overbooked {
                Text("More planned than the day has left — be gentle with yourself, maybe move something to tomorrow.")
                    .font(.custom(T.fontBody, size: 13).weight(.medium))
                    .foregroundColor(T.textSec)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.surface))
        .tempaShadowSm()
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.custom(T.fontBody, size: 12).weight(.semibold))
                .foregroundColor(T.textSec)
        }
    }

    // MARK: - Period picker

    private var periodPicker: some View {
        HStack(spacing: 6) {
            ForEach(StatsPeriod.allCases, id: \.self) { p in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { period = p }
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                } label: {
                    Text(p.label)
                        .font(.custom(T.fontHeader, size: 14).weight(.bold))
                        .foregroundColor(period == p ? T.text : T.textSec)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            // The pill glides between options instead of jumping.
                            if period == p {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(T.surface)
                                    .matchedGeometryEffect(id: "periodSel", in: pickerNS)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.bgWarm))
    }

    // MARK: - Stat tiles

    private func statTiles(_ s: StatsEngine.PeriodStats) -> some View {
        HStack(spacing: 10) {
            statTile(value: "\(s.doneCount)", label: String(localized: "done", bundle: .appLanguage), sub: String(localized: "of \(s.plannedCount) planned", bundle: .appLanguage))
            statTile(value: hm(s.doneMinutes), label: String(localized: "task time", bundle: .appLanguage), sub: period == .today ? String(localized: "today", bundle: .appLanguage) : (period == .week ? String(localized: "this week", bundle: .appLanguage) : String(localized: "this month", bundle: .appLanguage)))
            statTile(value: s.plannedCount > 0 ? "\(Int((Double(s.doneCount) / Double(s.plannedCount) * 100).rounded()))%" : "—",
                     label: String(localized: "follow-through", bundle: .appLanguage), sub: String(localized: "done vs planned", bundle: .appLanguage))
        }
    }

    private func statTile(value: String, label: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.custom(T.fontHeader, size: 22).weight(.heavy))
                .foregroundColor(T.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.custom(T.fontHeader, size: 12).weight(.bold))
                .foregroundColor(T.textSec)
            Text(sub)
                .font(.custom(T.fontBody, size: 11).weight(.medium))
                .foregroundColor(T.textTer)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.surface))
        .tempaShadowSm()
    }

    // MARK: - Completion chart (week / month)

    private func chartCard(_ s: StatsEngine.PeriodStats) -> some View {
        let maxVal = max(s.days.map { max($0.done, $0.planned) }.max() ?? 0, 1)
        let isWeek = period == .week
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PLANNED VS DONE")
                    .font(.custom(T.fontHeader, size: 12).weight(.heavy))
                    .tracking(1.2)
                    .foregroundColor(T.textSec)
                Spacer()
                legendDot(color: T.secondary, text: String(localized: "done", bundle: .appLanguage))
                legendDot(color: T.secondary.opacity(0.22), text: String(localized: "planned", bundle: .appLanguage))
            }

            if s.doneCount == 0 && s.plannedCount == 0 {
                Text("Nothing here yet for this period — your days will show up here.")
                    .font(.custom(T.fontBody, size: 13).weight(.medium))
                    .foregroundColor(T.textTer)
                    .padding(.vertical, 16)
            } else {
                HStack(alignment: .bottom, spacing: isWeek ? 8 : 3) {
                    ForEach(Array(s.days.enumerated()), id: \.element.id) { i, day in
                        let isToday = Calendar.current.isDateInToday(day.date)
                        VStack(spacing: 5) {
                            ZStack(alignment: .bottom) {
                                if day.planned > 0 {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(T.secondary.opacity(0.22))
                                        .frame(height: max(6, 80 * CGFloat(day.planned) / CGFloat(maxVal)))
                                }
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(isToday ? T.primary : T.secondary.opacity(day.done > 0 ? 1 : 0.18))
                                    .frame(height: day.done > 0 ? max(10, 80 * CGFloat(day.done) / CGFloat(maxVal)) : 4)
                            }
                            .frame(maxHeight: 80, alignment: .bottom)
                            .scaleEffect(y: chartsShown ? 1 : 0.02, anchor: .bottom)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(i) * 0.035), value: chartsShown)
                            if isWeek {
                                Text(weekdayLetter(day.date))
                                    .font(.custom(T.fontHeader, size: 10).weight(.bold))
                                    .foregroundColor(isToday ? T.primary : T.textTer)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: isWeek ? 100 : 88, alignment: .bottom)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.surface))
        .tempaShadowSm()
    }

    // MARK: - Golden hours (weekday × hour heatmap)

    private func heatmapCard(_ h: StatsEngine.HourlyActivity) -> some View {
        // Visible rows: the 8:00–22:00 core, stretched to any bucket that has data.
        var lo = 4, hi = 10
        if h.maxCount > 0 {
            for d in 0..<7 {
                for b in 0..<12 where h.grid[d][b] > 0 {
                    lo = min(lo, b)
                    hi = max(hi, b)
                }
            }
        }
        let buckets = Array(lo...hi)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YOUR GOLDEN HOURS")
                    .font(.custom(T.fontHeader, size: 12).weight(.heavy))
                    .tracking(1.2)
                    .foregroundColor(T.textSec)
                Spacer()
                Text("LAST 4 WEEKS")
                    .font(.custom(T.fontHeader, size: 10).weight(.bold))
                    .tracking(1)
                    .foregroundColor(T.textTer)
            }

            if h.maxCount == 0 {
                Text("As you complete tasks, you'll see when in the week you shine.")
                    .font(.custom(T.fontBody, size: 13).weight(.medium))
                    .foregroundColor(T.textTer)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Color.clear.frame(width: 30, height: 1)
                        ForEach(0..<7, id: \.self) { d in
                            Text(h.weekdayLetters[d])
                                .font(.custom(T.fontHeader, size: 10).weight(.bold))
                                .foregroundColor(T.textTer)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(buckets, id: \.self) { b in
                        HStack(spacing: 4) {
                            Text(Self.hourAxisLabel(b * 2))
                                .font(.custom(T.fontBody, size: 10).weight(.semibold))
                                .foregroundColor(T.textTer)
                                .frame(width: 30, alignment: .trailing)
                            ForEach(0..<7, id: \.self) { d in
                                let count = h.grid[d][b]
                                let isPeak = d == h.peakDay && b == h.peakBucket
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(cellColor(count: count, max: h.maxCount, isPeak: isPeak))
                                    .frame(height: 16)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }

                if let pd = h.peakDay, let pb = h.peakBucket {
                    Text("You're at your best on \(h.weekdayNames[pd])s around \(Self.hourString(pb * 2))–\(Self.hourString(pb * 2 + 2)).")
                        .font(.custom(T.fontBody, size: 13).weight(.medium))
                        .foregroundColor(T.textSec)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.surface))
        .tempaShadowSm()
    }

    private func cellColor(count: Int, max maxCount: Int, isPeak: Bool) -> Color {
        guard count > 0 else { return T.bgWarm }
        if isPeak { return T.primary }
        return T.secondary.opacity(0.22 + 0.78 * Double(count) / Double(maxCount))
    }

    /// Hour of day rendered the way the user's region says a clock should look:
    /// "14:00" in 24-hour regions, "2:00 PM" in the US/Canada.
    static func hourString(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour % 24, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(Date.FormatStyle(locale: AppLanguage.current.locale).hour().minute())
    }

    /// Compact heatmap axis label: "14" in 24-hour regions, "2 p" in 12-hour ones.
    static func hourAxisLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour % 24, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(Date.FormatStyle(locale: AppLanguage.current.locale).hour(.defaultDigits(amPM: .narrow)))
    }

    // MARK: - Focus time

    private var focusCard: some View {
        let total = focusDays.reduce(0) { $0 + $1.minutes }
        let maxMin = max(focusDays.map(\.minutes).max() ?? 0, 1)
        let isWeek = period == .week
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("FOCUS TIME")
                    .font(.custom(T.fontHeader, size: 12).weight(.heavy))
                    .tracking(1.2)
                    .foregroundColor(T.textSec)
                Spacer()
                Image(systemName: "timer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(T.primary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(hm(total))
                    .font(.custom(T.fontHeader, size: 30).weight(.heavy))
                    .tracking(-0.5)
                    .foregroundColor(T.text)
                Text(period == .today ? "focused today" : "focused this \(period == .week ? "week" : "month")")
                    .font(.custom(T.fontBody, size: 14).weight(.medium))
                    .foregroundColor(T.textSec)
            }

            if total == 0 {
                Text("No focus sessions in this period — the timer's there whenever you're ready.")
                    .font(.custom(T.fontBody, size: 13).weight(.medium))
                    .foregroundColor(T.textTer)
                    .fixedSize(horizontal: false, vertical: true)
            } else if period != .today {
                HStack(alignment: .bottom, spacing: isWeek ? 8 : 3) {
                    ForEach(Array(focusDays.enumerated()), id: \.element.id) { i, day in
                        let isToday = Calendar.current.isDateInToday(day.date)
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isToday ? T.primary : T.primary.opacity(day.minutes > 0 ? 0.55 : 0.14))
                                .frame(height: day.minutes > 0 ? max(8, 56 * CGFloat(day.minutes) / CGFloat(maxMin)) : 4)
                                .frame(maxHeight: 56, alignment: .bottom)
                                .scaleEffect(y: chartsShown ? 1 : 0.02, anchor: .bottom)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(i) * 0.035), value: chartsShown)
                            if isWeek {
                                Text(weekdayLetter(day.date))
                                    .font(.custom(T.fontHeader, size: 10).weight(.bold))
                                    .foregroundColor(isToday ? T.primary : T.textTer)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: isWeek ? 76 : 62, alignment: .bottom)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.surface))
        .tempaShadowSm()
    }

    private func weekdayLetter(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.current.locale
        f.dateFormat = "EEEEE"
        return f.string(from: d)
    }

    // MARK: - Where the time goes

    private var categoryCard: some View {
        let maxMin = max(cats.map { max($0.doneMin, $0.plannedMin) }.max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 14) {
            Text("WHERE YOUR TIME GOES")
                .font(.custom(T.fontHeader, size: 12).weight(.heavy))
                .tracking(1.2)
                .foregroundColor(T.textSec)

            ForEach(cats) { c in
                let cc = Cat.named(c.category)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(cc.solid).frame(width: 9, height: 9)
                            Text(catDisplayName(c.category))
                                .font(.custom(T.fontHeader, size: 13).weight(.bold))
                                .foregroundColor(T.text)
                        }
                        Spacer()
                        Text(c.doneMin > 0 ? "\(hm(c.doneMin)) done · \(hm(c.plannedMin)) planned" : "\(hm(c.plannedMin)) planned")
                            .font(.custom(T.fontBody, size: 12).weight(.medium))
                            .foregroundColor(T.textSec)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(T.bgWarm)
                            Capsule().fill(cc.bg)
                                .frame(width: geo.size.width * CGFloat(c.plannedMin) / CGFloat(maxMin))
                            Capsule().fill(cc.solid)
                                .frame(width: geo.size.width * CGFloat(c.doneMin) / CGFloat(maxMin))
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.surface))
        .tempaShadowSm()
    }

    // MARK: - Streak

    private func streakCard(_ s: StatsEngine.StreakInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("STREAK")
                    .font(.custom(T.fontHeader, size: 12).weight(.heavy))
                    .tracking(1.2)
                    .foregroundColor(T.textSec)
                Spacer()
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(T.primary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(s.current)")
                    .font(.custom(T.fontHeader, size: 34).weight(.heavy))
                    .foregroundColor(T.text)
                Text(s.current == 1 ? "day in a row" : "days in a row")
                    .font(.custom(T.fontBody, size: 14).weight(.medium))
                    .foregroundColor(T.textSec)
                Spacer()
                // Last 7 days, oldest → today.
                HStack(spacing: 5) {
                    ForEach(Array(s.last7.enumerated()), id: \.offset) { _, hit in
                        Circle()
                            .fill(hit ? T.secondary : T.bgWarm)
                            .frame(width: 10, height: 10)
                    }
                }
            }

            if s.best > 0 {
                HStack(spacing: 14) {
                    Text("Best streak: \(s.best) \(s.best == 1 ? "day" : "days")")
                    if s.bestDayCount > 0, let d = s.bestDayDate {
                        Text("Best day: \(s.bestDayCount) tasks · \(d.formatted(.dateTime.month(.abbreviated).day().locale(AppLanguage.current.locale)))")
                    }
                }
                .font(.custom(T.fontBody, size: 12).weight(.semibold))
                .foregroundColor(T.textTer)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.surface))
        .tempaShadowSm()
    }

    // MARK: - Helpers

    private func hm(_ minutes: Int) -> String {
        let m = max(0, minutes)
        if m >= 60 {
            let h = m / 60
            let r = m % 60
            return r > 0 ? "\(h)h \(r)m" : "\(h)h"
        }
        return "\(m)m"
    }
}

#Preview {
    MeView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environment(SettingsStore(context: PersistenceController.preview.container.viewContext))
}
