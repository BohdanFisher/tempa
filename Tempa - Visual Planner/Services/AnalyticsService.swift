import Foundation
import PostHog

enum AnalyticsEvent: String {
    case onboardingScreenView = "onboarding_screen_view"
    case onboardingCompleted = "onboarding_completed"
    case paywallShown = "paywall_shown"
    case paywallProductSelected = "paywall_product_selected"
    case paywallCTATapped = "paywall_cta_tapped"
    case trialStarted = "trial_started"
    case subscriptionPurchased = "subscription_purchased"
    case subscriptionCancelled = "subscription_cancelled"
    case taskBreakdownRequested = "task_breakdown_requested"
    case taskBreakdownAccepted = "task_breakdown_accepted"
    case taskCompleted = "task_completed"
    case taskStarted = "task_started"
    case focusSessionStarted = "focus_session_started"
    case focusSessionCompleted = "focus_session_completed"
    case welcomeBackShown = "welcome_back_shown"
    case dayComplete = "day_complete"
}

/// Behavioral counters only — never task titles, names, or anything typed by
/// the user: for this audience that's de facto medical data. The phc_ key is
/// PostHog's public write-only project token, safe to ship in the binary.
final class AnalyticsService {
    static let shared = AnalyticsService()

    private static var configured = false

    /// Call once at launch. DEBUG builds stay silent unless launched with
    /// "-analytics-debug YES", so simulator runs and owner test cycles don't
    /// pollute the funnel numbers.
    static func configure() {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "analytics-debug") else { return }
        #endif
        let config = PostHogConfig(
            projectToken: "phc_mK4TwzdB2Hv4Gnu3Yvx6qxVPtY4j5xsRe6ZCQ2dN2u6G",
            host: "https://eu.i.posthog.com"
        )
        config.captureApplicationLifecycleEvents = true
        PostHogSDK.shared.setup(config)
        TikTokEvents.configure()
        configured = true
    }

    func track(_ event: AnalyticsEvent, properties: [String: Any] = [:]) {
        guard Self.configured else { return }
        PostHogSDK.shared.capture(event.rawValue, properties: properties)
        TikTokEvents.forward(event, properties: properties)
    }
}
