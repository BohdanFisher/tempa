import Foundation
import PostHog

enum AnalyticsEvent: String {
    case onboardingScreenView = "onboarding_screen_view"
    case onboardingCompleted = "onboarding_completed"
    /// The calendar ask, answered. "source" (onboarding | settings),
    /// "provider" (apple | google), "outcome" (connected | denied | skipped |
    /// not_granted | failed | disconnected) and counts — never anything that
    /// is IN a calendar.
    case calendarSyncResult = "calendar_sync_result"
    case paywallShown = "paywall_shown"
    case paywallProductSelected = "paywall_product_selected"
    case paywallCTATapped = "paywall_cta_tapped"
    case trialStarted = "trial_started"
    case subscriptionPurchased = "subscription_purchased"
    /// A paid transaction that arrived OUTSIDE the paywall — a trial that
    /// converted, a renewal, an Ask-to-Buy approval. Carries "kind".
    case subscriptionRenewed = "subscription_renewed"
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

    /// DEBUG builds stay silent unless launched with "-analytics-debug YES",
    /// so simulator runs and owner test cycles don't pollute the funnel
    /// numbers — one gate shared by every SDK, including the ones that must
    /// start from the app delegate rather than from configure().
    static var isEnabled: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "analytics-debug")
        #else
        return true
        #endif
    }

    /// A Release build that is NOT the App Store one: TestFlight (sandbox
    /// App Store) or a Release run on the Simulator. Its purchases are free
    /// and fake, and the ad SDKs auto-log launches and purchases on their
    /// own — so the ad channels stay dark there while PostHog keeps the
    /// funnel data. DEBUG builds are excluded on purpose: they have their
    /// own gate, and an Xcode build on a real phone carries a
    /// "sandboxReceipt" too, which would lock the owner out of the
    /// platforms' test consoles. (The receipt file name is Apple's
    /// documented tell; the API is deprecated but still the only
    /// synchronous, prompt-free check.)
    static var isSandboxBuild: Bool {
        #if DEBUG
        return false
        #elseif targetEnvironment(simulator)
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    /// The ad platforms only: enabled AND a real App Store build.
    static var adSDKsEnabled: Bool { isEnabled && !isSandboxBuild }

    /// Call once at launch.
    static func configure() {
        guard isEnabled else { return }
        let config = PostHogConfig(
            projectToken: "phc_mK4TwzdB2Hv4Gnu3Yvx6qxVPtY4j5xsRe6ZCQ2dN2u6G",
            host: "https://eu.i.posthog.com"
        )
        config.captureApplicationLifecycleEvents = true
        PostHogSDK.shared.setup(config)
        TikTokEvents.configure()
        configured = true
    }

    /// Ad platforms must only ever see real money. Purchase events carry an
    /// "environment" (from StoreKit's Transaction.environment); anything but
    /// production — sandbox, Xcode's local store, the dev simulation — stays
    /// in PostHog for debugging and never reaches TikTok or Meta. DEBUG
    /// builds are exempt so "-analytics-debug YES" can rehearse the full
    /// chain against the platforms' test consoles.
    static func isRealMoney(_ properties: [String: Any]) -> Bool {
        #if DEBUG
        return true
        #else
        return (properties["environment"] as? String) == "production"
        #endif
    }

    /// The amount a PAID event may report to an ad platform: the price it
    /// carries, and only when it is real money. A free promo/offer-code
    /// transaction (price 0) or one whose price StoreKit couldn't tell yet
    /// must not become a $0 Purchase in Meta's value optimization.
    static func paidAmount(_ properties: [String: Any]) -> Double? {
        guard isRealMoney(properties),
              let price = properties["price"] as? Double, price > 0 else { return nil }
        return price
    }

    func track(_ event: AnalyticsEvent, properties: [String: Any] = [:]) {
        guard Self.configured else { return }
        PostHogSDK.shared.capture(event.rawValue, properties: properties)
        TikTokEvents.forward(event, properties: properties)
        MetaEvents.forward(event, properties: properties)
    }
}
