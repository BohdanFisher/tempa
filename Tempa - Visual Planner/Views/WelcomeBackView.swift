import SwiftUI
import CoreData

struct WelcomeBackView: View {
    @Environment(\.managedObjectContext) private var viewContext
    /// Primary CTA — close and open the add-task flow.
    let onPlan: () -> Void
    /// Skip — just close.
    let onDismiss: () -> Void

    /// Real completions over the last 7 days (oldest first) — no placeholder numbers.
    @State private var week: StatsEngine.PeriodStats?
    @State private var heartPulse = false

    private static let dayLetterFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEEE"; return f   // narrow weekday: M, T, W…
    }()
    private static let rangeFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMMd"); return f
    }()

    /// Squares for the recap strip: weekday letter + intensity relative to the best day.
    private var weekData: [(String, Double)] {
        guard let week else { return [] }
        let maxDone = week.days.map(\.done).max() ?? 0
        return week.days.map { d in
            (Self.dayLetterFmt.string(from: d.date),
             maxDone > 0 ? Double(d.done) / Double(maxDone) : 0)
        }
    }

    /// e.g. "Jun 16–22" or "Jun 28 – Jul 4" across a month boundary.
    private var rangeLabel: String {
        guard let days = week?.days, let f = days.first?.date, let l = days.last?.date else { return "" }
        let cal = Calendar.current
        if cal.isDate(f, equalTo: l, toGranularity: .month) {
            return "\(Self.rangeFmt.string(from: f))–\(cal.component(.day, from: l))"
        }
        return "\(Self.rangeFmt.string(from: f)) – \(Self.rangeFmt.string(from: l))"
    }

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        heartIcon
                            .padding(.top, 24)

                        Text("WELCOME BACK")
                            .font(.custom(T.fontHeader, size: 12).weight(.heavy))
                            .tracking(2)
                            .foregroundColor(T.primary)
                            .padding(.top, 20)

                        Text("You took a few\ndays off. That's okay.")
                            .font(.custom(T.fontHeader, size: 36).weight(.heavy))
                            .tracking(-0.7)
                            .foregroundColor(T.text)
                            .lineSpacing(2)
                            .padding(.top, 8)

                        Text("Tempa doesn't keep streaks or scores. Let's pick a small thing for today — that's enough to find your tempo again.")
                            .font(.custom(T.fontBody, size: 16).weight(.medium))
                            .foregroundColor(T.textSec)
                            .lineSpacing(4)
                            .padding(.top, 16)

                        recapCard
                            .padding(.top, 26)
                    }
                    .padding(.horizontal, 22)
                }

                VStack(spacing: 14) {
                    TempaButton(label: "Plan something small", variant: .primary, size: .lg, fullWidth: true, showArrow: true) {
                        onPlan()
                    }

                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        onDismiss()
                    } label: {
                        Text("Skip — just open my day")
                            .font(.custom(T.fontHeader, size: 14).weight(.bold))
                            .foregroundColor(T.textSec)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            week = StatsEngine.periodStats(daysBack: 7, context: viewContext)
        }
    }

    // MARK: - Heart Icon

    private var heartIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(lightHex: "#FFE9E1", darkHex: "#2C1F18"), Color(hex: "#FFD2BE")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 64, height: 64)

            Image(systemName: "heart.fill")
                .font(.system(size: 28))
                .foregroundColor(T.primaryDeep)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color(hex: "#FF7A59").opacity(0.25), lineWidth: 1)
                .frame(width: 80, height: 80)
                // A soft heartbeat — welcoming, not demanding.
                .scaleEffect(heartPulse ? 1.12 : 0.98)
                .opacity(heartPulse ? 0.35 : 0.9)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                        heartPulse = true
                    }
                }
        }
    }

    // MARK: - Recap Card

    private var recapCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("What you did last week")
                    .font(.custom(T.fontHeader, size: 15).weight(.heavy))
                    .foregroundColor(T.text)
                Spacer()
                Text(rangeLabel)
                    .font(.custom(T.fontBody, size: 12).weight(.semibold))
                    .foregroundColor(T.textSec)
            }

            HStack(spacing: 8) {
                ForEach(Array(weekData.enumerated()), id: \.offset) { i, day in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(day.1 == 0 ? T.bgWarm : Color(hex: "#4EC8B0").opacity(0.2 + day.1 * 0.6))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                if day.1 == 0 {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(T.textTer, style: StrokeStyle(lineWidth: 1, dash: [4]))
                                }
                            }

                        Text(day.0)
                            .font(.custom(T.fontBody, size: 11).weight(.semibold))
                            .foregroundColor(T.textSec)
                    }
                    .staggerIn(i, baseDelay: 0.05)
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Cat.health.ink)

                VStack(alignment: .leading, spacing: 1) {
                    let n = week?.doneCount ?? 0
                    if n > 0 {
                        Text(n == 1 ? "You got 1 thing done" : "You got \(n) things done")
                            .font(.custom(T.fontHeader, size: 14).weight(.bold))
                            .foregroundColor(T.text)
                        Text("Starting is the hard part — you did it \(n == 1 ? String(localized: "once") : String(localized: "\(n) times")).")
                            .font(.custom(T.fontBody, size: 12).weight(.medium))
                            .foregroundColor(T.textSec)
                    } else {
                        Text("Last week was quiet")
                            .font(.custom(T.fontHeader, size: 14).weight(.bold))
                            .foregroundColor(T.text)
                        Text("That's okay. One small thing today is plenty.")
                            .font(.custom(T.fontBody, size: 12).weight(.medium))
                            .foregroundColor(T.textSec)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Cat.health.bg)
            )
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(T.surface)
        )
        .tempaShadowSm()
    }

    // MARK: - Static helpers

    static func shouldShow() -> Bool {
        let lastOpen = UserDefaults.standard.object(forKey: "tempa_last_app_open") as? Date ?? Date()
        let hoursSinceOpen = Date().timeIntervalSince(lastOpen) / 3600
        guard hoursSinceOpen > 36 else { return false }
        let lastShown = UserDefaults.standard.object(forKey: "tempa_welcome_back_last_shown") as? Date ?? .distantPast
        return Date().timeIntervalSince(lastShown) / 3600 > 36
    }

    static func markShown() {
        UserDefaults.standard.set(Date(), forKey: "tempa_welcome_back_last_shown")
    }

    static func recordAppOpen() {
        UserDefaults.standard.set(Date(), forKey: "tempa_last_app_open")
    }
}
