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
    /// Footer contact line; nil when the document carries its own contact section.
    var contact: String? = nil

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
                        if !s.heading.isEmpty {
                            Text(s.heading)
                                .font(.custom(T.fontHeader, size: 15).weight(.heavy))
                                .foregroundColor(T.text)
                        }
                        Text(s.body)
                            .font(.custom(T.fontBody, size: 14).weight(.medium))
                            .foregroundColor(T.textSec)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let contact {
                    Text(contact)
                        .font(.custom(T.fontBody, size: 13).weight(.medium))
                        .foregroundColor(T.textSec)
                        .padding(.top, 6)
                        .padding(.bottom, 24)
                }
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
        ], contact: "Questions? support@tempa-planner.app")
    }
}

// MARK: - Terms of Service

struct TermsSheet: View {
    var body: some View {
        LegalSheet(title: "Terms of Service", updated: "July 15, 2026", sections: [
            LegalSection(
                heading: "",
                body: "These Terms of Service (\"Terms\") govern your use of the Tempa mobile application (the \"App\"). By downloading or using the App, you agree to these Terms. If you do not agree, do not use the App."
            ),
            LegalSection(
                heading: "1. The service",
                body: "Tempa is a personal day-planning application offering task capture (including by voice), AI-assisted scheduling, color-coded time blocks, and focus sessions. We may add, change, or remove features as the App evolves."
            ),
            LegalSection(
                heading: "2. Your account and acceptable use",
                body: "• You are responsible for the content you add to the App and for keeping your device secure.\n• You agree not to misuse the App — including attempting to disrupt the service, reverse-engineer it except where permitted by law, or use it for unlawful purposes.\n• You must be at least 13 years old (or the minimum age in your jurisdiction) to use the App."
            ),
            LegalSection(
                heading: "3. Subscriptions and billing",
                body: "• Some features require a paid subscription (\"Tempa Plus\"), billed through your Apple App Store account.\n• Where a free trial is offered, your subscription begins automatically at the end of the trial unless cancelled at least 24 hours before it ends.\n• Subscriptions renew automatically until cancelled in your App Store settings. Cancellation takes effect at the end of the current billing period.\n• Refunds are handled by Apple under App Store policies."
            ),
            LegalSection(
                heading: "4. AI-generated content",
                body: "The App uses AI to suggest plans and schedules. Suggestions are generated automatically and may be inaccurate or unsuitable for your situation. They are provided for convenience only and are not professional, medical, or psychological advice. You remain responsible for the decisions you make."
            ),
            LegalSection(
                heading: "5. Your content",
                body: "You retain all rights to the content you create in the App. You grant us a limited license to process that content solely to provide the App's features (for example, transcribing voice input or generating a schedule). We do not claim ownership of your content."
            ),
            LegalSection(
                heading: "6. Intellectual property",
                body: "The App, including its design, branding, and software, is owned by us and protected by intellectual-property laws. These Terms do not grant you any right to use the Tempa name, logo, or branding."
            ),
            LegalSection(
                heading: "7. Disclaimer of warranties",
                body: "The App is provided \"as is\" and \"as available\", without warranties of any kind, express or implied, including fitness for a particular purpose and non-infringement. We do not warrant that the App will be uninterrupted or error-free."
            ),
            LegalSection(
                heading: "8. Limitation of liability",
                body: "To the maximum extent permitted by law, we are not liable for any indirect, incidental, special, or consequential damages, or for loss of data, arising from your use of the App. Our total liability for any claim relating to the App will not exceed the amount you paid us in the 12 months before the claim arose."
            ),
            LegalSection(
                heading: "9. Termination",
                body: "You may stop using the App at any time. We may suspend or terminate access if you materially breach these Terms. Sections that by their nature should survive termination (including 5–8) will survive."
            ),
            LegalSection(
                heading: "10. Changes to these Terms",
                body: "We may update these Terms from time to time. If we make material changes, we will notify you within the App or by other reasonable means. Continuing to use the App after changes take effect constitutes acceptance of the revised Terms."
            ),
            LegalSection(
                heading: "11. Contact",
                body: "Questions about these Terms? Email us at support@tempa-planner.app."
            ),
        ])
    }
}
