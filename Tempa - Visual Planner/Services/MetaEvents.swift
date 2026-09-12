import Foundation
import UIKit
import FBSDKCoreKit

/// Ad-attribution signals for Meta (Facebook / Instagram) campaigns — the
/// same narrow channel as TikTokEvents: Meta only ever receives the handful
/// of standard events its delivery models can optimize on, never
/// screen-by-screen behavior and never anything the user typed.
///
/// Install and app activation are logged by the SDK itself ("Log in-app
/// events automatically" — one switch in the app dashboard that also covers
/// purchases, and install campaigns can't live without the install half).
/// StartTrial and Purchase are STILL sent by hand, from the one place a
/// verified transaction is known: the SDK's own purchase observer only
/// polls StoreKit (hourly, on foreground, and right after a manual money
/// event) and has a history of missing trials. Both copies carry the same
/// name / value / currency / product ID, which is exactly what the SDK's
/// IAP dedupe (v18+) keys on — the duplicate is flagged and dropped
/// server-side. A trial never counts as revenue, a restore never counts as
/// a sale, and the values match what PostHog, RevenueCat and TikTok saw.
///
/// Delivery: the SDK batches and flushes on its own timer (and on every app
/// foreground); the money events are flushed immediately on top of that.
/// Undelivered events persist on disk and go out on the next launch.
///
/// App ID and client token identify the app, not a person; Meta documents
/// both as shippable in the binary (they live in Info.plist).
enum MetaEvents {
    private static var configured = false

    /// Called from AppDelegate — the SDK insists on the didFinishLaunching
    /// hook — but only when the ad SDKs are enabled, so DEBUG builds stay
    /// out of the campaign data unless launched with "-analytics-debug YES"
    /// (those runs show up in Events Manager's Test Events tab and in the
    /// Xcode console), and TestFlight builds stay out entirely.
    static func configure(application: UIApplication,
                          launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        guard AnalyticsService.adSDKsEnabled else { return }
        #if DEBUG
        Settings.shared.enableLoggingBehavior(.appEvents)
        #endif
        ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
        configured = true
    }

    /// Fan-out from AnalyticsService.track — one call site, so the PostHog
    /// funnel and the Meta signals can never drift apart.
    static func forward(_ event: AnalyticsEvent, properties: [String: Any]) {
        guard configured else { return }
        let productID = properties["product"] as? String
        let currency = properties["currency"] as? String ?? "USD"
        var params: [AppEvents.ParameterName: Any] = [:]
        if let productID {
            params[.contentID] = productID
            params[.contentType] = "product"
        }

        switch event {
        case .onboardingCompleted:
            AppEvents.shared.logEvent(.completedRegistration,
                                      parameters: [.registrationMethod: "onboarding"])
        case .paywallShown:
            AppEvents.shared.logEvent(.viewedContent,
                                      parameters: [.contentID: "paywall", .contentType: "paywall"])
        case .paywallCTATapped:
            AppEvents.shared.logEvent(.initiatedCheckout, parameters: params)
        case .trialStarted:
            guard AnalyticsService.isRealMoney(properties) else { return }
            // A trial hasn't paid anything yet — value 0 keeps Meta's revenue
            // math honest; the money arrives as Purchase.
            params[.currency] = currency
            addTransaction(&params, properties)
            AppEvents.shared.logEvent(.startTrial, valueToSum: 0, parameters: params)
            AppEvents.shared.flush()
        case .subscriptionPurchased, .subscriptionRenewed:
            // ONE money event per paid transaction, and it's Purchase
            // (fb_mobile_purchase): the only event Ads Manager's ROAS and
            // value optimization read. Sending Subscribe as well would
            // double every dollar in Meta's revenue roll-ups — the SDK can't
            // dedupe across two event names. Covers the direct monthly buy,
            // the yearly trial converting on day 3, and every renewal.
            guard let price = AnalyticsService.paidAmount(properties) else { return }
            params[.numItems] = 1
            addTransaction(&params, properties)
            // logPurchase flushes the queue on its own.
            AppEvents.shared.logPurchase(amount: price, currency: currency, parameters: params)
        default:
            break
        }
    }

    /// The App Store transaction ID doubles as Meta's order ID — it's how a
    /// server-side copy of the same sale (a future Conversions API feed)
    /// would be deduplicated against this one.
    private static func addTransaction(_ params: inout [AppEvents.ParameterName: Any],
                                       _ properties: [String: Any]) {
        guard let id = properties["transaction_id"] as? String else { return }
        params[.orderID] = id
        params[AppEvents.ParameterName("fb_transaction_id")] = id
    }
}
