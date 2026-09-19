import SwiftUI
import CoreData

/// The AI tab: two doors into the same place.
///
/// Speak it is the brain dump — you talk, the AI splits it into tasks and
/// puts each one in a free slot. Ask Tempa is the short conversation for the
/// days when the head is foggy. Both end at the same review list, which is
/// what the line at the bottom promises.
///
/// Nothing else lives here on purpose. The room under the two doors stays
/// empty: this screen is a door, not a dashboard, and anything worth showing
/// (what is left today, what is next) is already on Home.
struct AIView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showVoice = false
    @State private var showAskAI = false
    @State private var showDayPlan = false
    /// Set while the recorder / chat is still closing: the plan sheet waits
    /// for the cover to be gone, or the two fight over the presentation slot.
    @State private var pendingPlan = false
    @State private var dumpText = ""

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text("AI")
                    .font(.custom(T.fontHeader, size: 30).weight(.heavy))
                    .tracking(-0.6)
                    .foregroundColor(T.text)

                Text("Two ways in — whichever suits you right now.")
                    .font(.custom(T.fontBody, size: 13).weight(.medium))
                    .foregroundColor(T.textSec)
                    .lineSpacing(2)
                    .padding(.top, 5)
                    .padding(.bottom, 14)

                speakDoor
                askDoor

                Spacer(minLength: 12)

                Text("Both ways end in a list you check — nothing is added on its own.")
                    .font(.custom(T.fontBody, size: 12).weight(.medium))
                    .foregroundColor(T.textTer)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, TempaTabBar.contentClearance)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .fullScreenCover(isPresented: $showVoice) {
            AddTaskVoiceView { text in
                dumpText = text
                pendingPlan = true
            }
        }
        .fullScreenCover(isPresented: $showAskAI) {
            AddTaskAskAIView { text in
                dumpText = text
                pendingPlan = true
            }
        }
        // Present the day-plan only once the cover in front has fully gone.
        .onChange(of: showVoice) { _, shown in openPlanIfPending(shown) }
        .onChange(of: showAskAI) { _, shown in openPlanIfPending(shown) }
        .fullScreenCover(isPresented: $showDayPlan) {
            DayPlanReviewSheet(dump: dumpText) {}
        }
    }

    private func openPlanIfPending(_ shown: Bool) {
        guard !shown, pendingPlan else { return }
        pendingPlan = false
        showDayPlan = true
    }

    // MARK: - The doors

    /// Coral, with the signature waveform: the one that starts a brain dump.
    private var speakDoor: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showVoice = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    iconTile(filled: true) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    TempaWaveform(color: .white, bars: 11, maxHeight: 34, barWidth: 5, spacing: 5)
                        .frame(height: 34)
                }
                .frame(height: 60)
                .padding(.bottom, 16)

                Text("Speak it")
                    .font(.custom(T.fontHeader, size: 24).weight(.heavy))
                    .tracking(-0.4)
                    .foregroundColor(.white)
                Text("Say everything that's on your mind. Tempa turns it into tasks and finds them free slots.")
                    .font(.custom(T.fontBody, size: 13).weight(.medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(T.primaryFill)
            )
            .tempaShadow()
        }
        .buttonStyle(SpringPressStyle(scale: 0.97))
        .padding(.bottom, 12)
    }

    /// The quiet one, with two lines of a conversation for a face.
    private var askDoor: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showAskAI = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    iconTile(filled: false) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(T.primary)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        bubble("Where do I start?", mine: false)
                        bubble("Let's have a look", mine: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 60)
                .padding(.bottom, 16)

                Text("Ask Tempa")
                    .font(.custom(T.fontHeader, size: 24).weight(.heavy))
                    .tracking(-0.4)
                    .foregroundColor(T.text)
                Text("A short conversation for a foggy head. It sees your day and names one thing to start with.")
                    .font(.custom(T.fontBody, size: 13).weight(.medium))
                    .foregroundColor(T.textSec)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(T.surface)
            )
            .tempaShadowSm()
        }
        .buttonStyle(SpringPressStyle(scale: 0.97))
    }

    private func iconTile<Content: View>(filled: Bool, @ViewBuilder content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 19, style: .continuous)
            .fill(filled ? AnyShapeStyle(Color.white.opacity(0.22)) : AnyShapeStyle(T.aiTint))
            .frame(width: 60, height: 60)
            .overlay(content())
    }

    private func bubble(_ text: LocalizedStringKey, mine: Bool) -> some View {
        Text(text)
            .font(.custom(T.fontBody, size: 11.5).weight(.medium))
            // T.text inverts with the theme, so the ink on it has to be T.bg —
            // the same pair the real chat uses for its own bubbles.
            .foregroundColor(mine ? T.bg : T.text)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 12, bottomLeadingRadius: mine ? 12 : 4,
                    bottomTrailingRadius: mine ? 4 : 12, topTrailingRadius: 12,
                    style: .continuous
                )
                .fill(mine ? AnyShapeStyle(T.text) : AnyShapeStyle(T.bgWarm))
            )
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }
}

#Preview {
    AIView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environment(SettingsStore(context: PersistenceController.preview.container.viewContext))
        .environment(SubscriptionManager.shared)
}
