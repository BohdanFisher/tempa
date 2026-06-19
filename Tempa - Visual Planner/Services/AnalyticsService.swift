import Foundation

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

final class AnalyticsService {
    static let shared = AnalyticsService()

    func track(_ event: AnalyticsEvent, properties: [String: Any] = [:]) {
        #if DEBUG
        return
        #else
        // TODO: PostHog integration
        // PHGPostHog.shared()?.capture(event.rawValue, properties: properties)
        print("[Analytics] \(event.rawValue) \(properties)")
        #endif
    }
}
