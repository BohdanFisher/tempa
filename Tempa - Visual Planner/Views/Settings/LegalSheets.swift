import SwiftUI

// In-app legal documents — Privacy Policy and Terms of Service — shown in the
// same sheet style as the old AI-privacy popup. Shared by Settings and the
// paywall footer. Plain-English, but written for maximum protection allowed
// by law (AS-IS, no warranties, liability cap, medical & reminder disclaimers).

// MARK: - Shared scaffold

private struct LegalSection: Identifiable {
    let id = UUID()
    let heading: String
    let body: String
}

private struct LegalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let updated: String
    let sections: [LegalSection]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(title)
                        .font(.custom(T.fontHeader, size: 24).weight(.heavy))
                        .foregroundColor(T.text)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(T.text)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(T.surface))
                    }
                }

                Text("Last updated: \(updated)")
                    .font(.custom(T.fontBody, size: 12).weight(.medium))
                    .foregroundColor(T.textTer)

                ForEach(sections) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.heading)
                            .font(.custom(T.fontHeader, size: 15).weight(.heavy))
                            .foregroundColor(T.text)
                        Text(s.body)
                            .font(.custom(T.fontBody, size: 14).weight(.medium))
                            .foregroundColor(T.textSec)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text("Questions? rybakbohdan@gmail.com")
                    .font(.custom(T.fontBody, size: 13).weight(.medium))
                    .foregroundColor(T.textSec)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
            }
            .padding(24)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(T.bg)
    }
}

// MARK: - Privacy Policy

struct PrivacyPolicySheet: View {
    var body: some View {
        LegalSheet(title: "Privacy Policy", updated: "July 5, 2026", sections: [
            LegalSection(
                heading: "The short version",
                body: "Your plans stay yours. Tempa has no accounts, no ads, no analytics and no servers of its own. Almost everything lives on your device."
            ),
            LegalSection(
                heading: "What stays on your device",
                body: "Your tasks, schedule, completions, focus history and stats are stored on your device and synced through your private iCloud (CloudKit). They are encrypted in your Apple account — we cannot read them."
            ),
            LegalSection(
                heading: "What is sent to AI",
                body: "Only the task text you type or speak is sent to Anthropic's API when you use an AI feature (break into steps, plan my day, Ask Tempa) — so it can be turned into a plan. Per Anthropic's API terms, it isn't used to train models. Your schedule, stats and everything else are never sent."
            ),
            LegalSection(
                heading: "Voice input",
                body: "Speech is transcribed by Apple's speech services on your device where available; Tempa only receives the resulting text. Audio is handled under Apple's privacy policy."
            ),
            LegalSection(
                heading: "Notifications",
                body: "Reminders and nudges are scheduled locally on your device. They never leave it."
            ),
            LegalSection(
                heading: "Purchases",
                body: "Subscriptions are processed entirely by Apple. We never see your payment details — only an anonymous receipt that says Pro is active."
            ),
            LegalSection(
                heading: "No tracking",
                body: "No ad networks, no tracking SDKs, no fingerprinting, no data brokers. We don't build profiles of you."
            ),
            LegalSection(
                heading: "Your control",
                body: "Delete a task and it's gone from your devices and your iCloud. Delete the app and its data goes with it (iCloud data can also be removed in iOS Settings → iCloud). There's no account to close because there's no account."
            ),
            LegalSection(
                heading: "Changes",
                body: "If this policy changes in a meaningful way, the app will say so. Continued use after changes means you accept the updated policy."
            ),
        ])
    }
}

// MARK: - Terms of Service

struct TermsSheet: View {
    var body: some View {
        LegalSheet(title: "Terms of Service", updated: "July 5, 2026", sections: [
            LegalSection(
                heading: "1. Agreement",
                body: "By downloading or using Tempa you agree to these terms. If you don't agree, please don't use the app."
            ),
            LegalSection(
                heading: "2. What Tempa is (and isn't)",
                body: "Tempa is a personal planning tool. It is not a medical device and does not provide medical, psychological or professional advice, diagnosis or treatment. It is not a substitute for care from a qualified professional. Always consult a professional about health decisions, including ADHD and medication."
            ),
            LegalSection(
                heading: "3. Reminders are best-effort",
                body: "Notifications and reminders can be delayed, altered or missed entirely — because of device settings, Focus modes, system behavior, battery optimization or software failures. You agree not to rely on Tempa as your only reminder for anything important, including medication, appointments or deadlines, and you accept full responsibility for the outcomes of missed or late reminders."
            ),
            LegalSection(
                heading: "4. AI-generated content",
                body: "AI features produce automated suggestions that may be inaccurate, incomplete or inappropriate for your situation. They are suggestions, not advice. You are solely responsible for reviewing them and for any action you take based on them."
            ),
            LegalSection(
                heading: "5. No warranties",
                body: "To the maximum extent permitted by applicable law, Tempa is provided \"as is\" and \"as available\", without warranties of any kind, express or implied — including merchantability, fitness for a particular purpose, accuracy, availability and non-infringement. We do not warrant that the app will be uninterrupted, error-free or that data will never be lost. Back up anything you can't afford to lose."
            ),
            LegalSection(
                heading: "6. Limitation of liability",
                body: "To the maximum extent permitted by applicable law, the developer shall not be liable for any indirect, incidental, special, consequential, exemplary or punitive damages, or for any loss of data, profits, goodwill, health outcomes, missed events, missed medication or missed obligations, arising out of or related to your use of (or inability to use) the app — even if advised of the possibility. The developer's total aggregate liability for all claims shall not exceed the amount you paid for the app in the 12 months before the claim, or USD 10, whichever is greater. Some jurisdictions don't allow certain exclusions; there, liability is limited to the maximum extent the law allows."
            ),
            LegalSection(
                heading: "7. Your responsibility",
                body: "You agree to use the app lawfully and at your own risk, and — to the extent permitted by law — to indemnify and hold the developer harmless from claims arising out of your use of the app or your breach of these terms."
            ),
            LegalSection(
                heading: "8. Subscriptions",
                body: "Tempa Pro is billed through your Apple account and renews automatically until cancelled at least 24 hours before the end of the period (manage in App Store → Subscriptions). Free-trial time, where offered, is forfeited on purchase. Refunds are handled exclusively by Apple under their policies."
            ),
            LegalSection(
                heading: "9. Intellectual property",
                body: "The app, its design, name and content belong to the developer. You get a personal, non-transferable, revocable licence to use the app on your Apple devices; you may not copy, modify, resell or reverse-engineer it except where the law expressly permits."
            ),
            LegalSection(
                heading: "10. App Store",
                body: "These terms are between you and the developer, not Apple. Apple has no obligation to provide maintenance or support and is not responsible for the app or any claims relating to it. Apple and its subsidiaries are third-party beneficiaries of these terms and may enforce them."
            ),
            LegalSection(
                heading: "11. Changes and termination",
                body: "We may update the app or these terms, or discontinue the app, at any time. Material changes will be signposted in the app; continued use means acceptance. We may suspend access for breach of these terms."
            ),
            LegalSection(
                heading: "12. Governing law",
                body: "These terms are governed by the laws of Ukraine, without affecting any mandatory consumer-protection rights of the country you live in. If any provision is found unenforceable, the rest remain in force."
            ),
        ])
    }
}
