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

                // Legal documents stay English end to end — verbatim keeps this
                // line out of the localization system with the body text.
                Text(verbatim: "Last updated: \(updated)")
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
    // Keep in step with website/privacy.html — the same sixteen sections, word
    // for word. Every claim here is a promise about what the code does: if a
    // data flow changes (a new SDK, anything new in an AI prompt, anything
    // about calendars), this text changes in the same commit.
    var body: some View {
        LegalSheet(title: "Privacy Policy", updated: "September 21, 2026", sections: [
            LegalSection(
                heading: "1. The short version",
                body: "Your plans stay yours. Tempa has no accounts and no servers of its own that hold your data — your tasks live on your device and in your own iCloud. A few services help the app work: AI planning, subscriptions, anonymous usage statistics and ad measurement. This page says exactly what each of them receives. We never sell your data, and nothing you type is ever used for advertising."
            ),
            LegalSection(
                heading: "2. What stays on your device",
                body: "Your tasks, schedule, completions, focus history and settings are stored on your device and synced through your private iCloud (CloudKit). They sit in your Apple account, out of our reach — we cannot read them."
            ),
            LegalSection(
                heading: "3. What is sent to AI",
                body: "When you use an AI feature (break into steps, plan my day, Ask Tempa), the text you typed or spoke is sent to Anthropic's API so it can be turned into a plan. So the plan fits your day, the request can also include the titles and times of your own tasks for the days involved, your wake time, your energy-dip time, and the current date and time zone. Events from your calendars are never included. Per Anthropic's API terms, this data isn't used to train models. Nothing is sent unless you use an AI feature."
            ),
            LegalSection(
                heading: "4. Voice input",
                body: "Speech is turned into text by Apple's speech recognition — on your device where available, otherwise on Apple's servers under Apple's privacy policy. Tempa only receives the resulting text and never stores audio."
            ),
            LegalSection(
                heading: "5. Your calendars",
                body: "Connecting a calendar is optional. With your permission, Tempa reads events from the calendars set up on your iPhone (iCloud, Google, Outlook and others) and shows them as blocks on your day, so your tasks are planned around them. Tempa only reads: it never adds, changes or deletes anything in your calendar. Imported events are kept like your tasks — on your device and in your own iCloud. They are never sent to us, to the AI, to analytics or to advertisers. Switch it off any time in Settings → Calendar, and the upcoming imported events are removed."
            ),
            LegalSection(
                heading: "6. Google Calendar",
                body: "If you choose to sign in with Google, Tempa asks for read-only access to your list of calendars and to their events. It uses this only to show your Google Calendar events on your day and to plan your tasks around them, on your device. The data goes straight from Google to your phone — Tempa has no server — and is stored only on your device and in your own iCloud. It is never shared with third parties, never used for advertising, and never used to train AI models. The sign-in token is kept in your iPhone's Keychain. Disconnect in Settings → Calendar and access is revoked and the upcoming imported events are removed; you can also remove Tempa's access at https://myaccount.google.com/permissions. Tempa's use and transfer of information received from Google APIs to any other app will adhere to the Google API Services User Data Policy (https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements."
            ),
            LegalSection(
                heading: "7. How your data is protected",
                body: "Everything Tempa sends or receives — to and from Google, Anthropic and Apple — travels encrypted over HTTPS (TLS). Google sign-in happens in Apple's secure sign-in window using OAuth 2.0 with PKCE, so Tempa never sees your Google password, and access is limited to the two read-only calendar permissions described above. The sign-in token is stored in the iOS Keychain, which iOS encrypts, and it is not synced to your other devices. Your tasks and imported calendar events are kept in Tempa's private storage on your iPhone, which iOS encrypts (Data Protection), and are synced only through your own private iCloud database, which Apple encrypts in transit and at rest and which we cannot access. Tempa has no server of its own that receives your data, so there is no copy of it on our side to be read, lost or sold. When you disconnect Google Calendar, Tempa also deletes the sign-in token and its cached calendar data from your device; events that already happened stay in your history like your own tasks until you delete them."
            ),
            LegalSection(
                heading: "8. Notifications",
                body: "Reminders and nudges are scheduled locally on your device. They never leave it."
            ),
            LegalSection(
                heading: "9. Purchases",
                body: "Subscriptions are processed entirely by Apple; we never see your payment details. So we know a subscription is active and can understand our revenue, the purchase record (product, price, dates and an anonymous app identifier — no name, no email) is shared with RevenueCat, our subscription analytics provider. If you installed Tempa from an Apple Search Ads ad, Apple's attribution token is passed along so we know which campaign worked."
            ),
            LegalSection(
                heading: "10. Anonymous usage statistics",
                body: "To see where the app confuses people, Tempa records anonymous events with PostHog, hosted in the EU: which onboarding screens were viewed, that a task was completed, a focus session started, the paywall shown, a calendar connected. Counters only — never task text, names, calendar contents or anything you type. Events carry a random identifier and basic device information (model, iOS version, app version, language, and an approximate region derived from your IP address). There are no accounts, so they are not tied to your identity."
            ),
            LegalSection(
                heading: "11. Ad measurement",
                body: "We advertise Tempa on TikTok, Meta (Facebook and Instagram) and Apple Search Ads. So those campaigns can be measured, the TikTok and Meta SDKs inside the app report a few standard events — install, app open, onboarding finished, paywall viewed, trial started, and a purchase with its value — along with the device information those SDKs collect (such as device model, iOS version, IP address and Apple's SKAdNetwork attribution data). Tempa never shows Apple's tracking prompt, so these SDKs don't receive your advertising identifier (IDFA). Nothing you type, no task and no calendar data is ever shared with them."
            ),
            LegalSection(
                heading: "12. This website",
                body: "tempa-planner.app uses Google Analytics to count visits and taps on the download button. It sets cookies and sees your IP address and browser details. It has no connection to what you do inside the app."
            ),
            LegalSection(
                heading: "13. Your control",
                body: "Delete a task and it's gone from your devices and your iCloud. Delete the app and its data goes with it (iCloud data can also be removed in iOS Settings → iCloud). Calendars can be switched off in Settings → Calendar or in iOS Settings → Privacy & Security → Calendars. There's no account to close because there's no account. To ask what statistics may be linked to your device, or to have them deleted, email us at support@tempa-planner.app."
            ),
            LegalSection(
                heading: "14. Children",
                body: "Tempa is not meant for children under 13, and we do not knowingly collect their data."
            ),
            LegalSection(
                heading: "15. Changes",
                body: "If this policy changes in a meaningful way, the app will say so. Continued use after changes means you accept the updated policy."
            ),
            LegalSection(
                heading: "16. Contact",
                body: "Questions about this policy? Email us at support@tempa-planner.app."
            ),
        ])
    }
}

// MARK: - Terms of Service

struct TermsSheet: View {
    var body: some View {
        LegalSheet(title: "Terms of Service", updated: "July 29, 2026", sections: [
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
