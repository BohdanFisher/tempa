import SwiftUI
import CoreData

struct WelcomeBackView: View {
    @Environment(\.managedObjectContext) private var viewContext
    let onDismiss: () -> Void

    private let weekData: [(String, Double)] = [
        ("M", 0.7), ("T", 0.4), ("W", 0.9), ("T", 0.2), ("F", 0), ("S", 0), ("S", 0),
    ]

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
                        onDismiss()
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
                Text("May 18–24")
                    .font(.custom(T.fontBody, size: 12).weight(.semibold))
                    .foregroundColor(T.textSec)
            }

            HStack(spacing: 8) {
                ForEach(Array(weekData.enumerated()), id: \.offset) { _, day in
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
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Cat.health.ink)

                VStack(alignment: .leading, spacing: 1) {
                    Text("You started 14 things")
                        .font(.custom(T.fontHeader, size: 14).weight(.bold))
                        .foregroundColor(T.text)
                    Text("Starting is the hard part. You did it 14 times.")
                        .font(.custom(T.fontBody, size: 12).weight(.medium))
                        .foregroundColor(T.textSec)
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
