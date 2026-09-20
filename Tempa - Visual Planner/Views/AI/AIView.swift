import SwiftUI
import CoreData

/// The AI tab IS the recorder.
///
/// Opening the tab puts the user one tap from talking: the same screen
/// "Speak it" has always led to, minus its chrome. Nothing is recorded until
/// the mic is tapped, and the mic is released the moment the tab is left.
/// Ask Tempa — the typed way in, for the days when talking isn't it — sits
/// under it as one plain button.
struct AIView: View {
    @State private var showAskAI = false
    @State private var showDayPlan = false
    /// Set while Ask Tempa is still closing: the plan sheet waits for the
    /// cover to be gone, or the two fight over the presentation slot.
    @State private var pendingPlan = false
    @State private var dumpText = ""

    var body: some View {
        VoiceCaptureView(home: .tab) { text in
            // Spoken and confirmed, straight into the review list.
            dumpText = text
            showDayPlan = true
        } footer: {
            askTempaButton
        }
        .fullScreenCover(isPresented: $showAskAI) {
            AddTaskAskAIView { text in
                dumpText = text
                pendingPlan = true
            }
        }
        .onChange(of: showAskAI) { _, shown in
            guard !shown, pendingPlan else { return }
            pendingPlan = false
            showDayPlan = true
        }
        .fullScreenCover(isPresented: $showDayPlan) {
            DayPlanReviewSheet(dump: dumpText) {}
        }
    }

    /// The other door, kept quiet on purpose: the mic is the point of this
    /// screen, this is the way out for a head that would rather type.
    private var askTempaButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showAskAI = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(T.primary)
                Text("Ask Tempa")
                    .font(.custom(T.fontHeader, size: 16).weight(.bold))
                    .foregroundColor(T.text)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.surface)
            )
            .tempaShadowSm()
        }
        .buttonStyle(SpringPressStyle(scale: 0.97))
        .padding(.bottom, TempaTabBar.contentClearance)
    }
}

#Preview {
    AIView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environment(SettingsStore(context: PersistenceController.preview.container.viewContext))
        .environment(SubscriptionManager.shared)
}
