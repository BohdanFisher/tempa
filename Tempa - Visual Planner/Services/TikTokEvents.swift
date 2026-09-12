import Foundation
import TikTokBusinessSDK

/// Ad-attribution signals for TikTok campaigns — a separate, much narrower
/// channel than PostHog: TikTok only ever receives the handful of standard
/// events its ad models can optimize on (install/launch are automatic), never
/// screen-by-screen behavior and never anything the user typed.
///
/// Delivery: the SDK flushes its queue every 15 seconds while the app runs and
/// again on foreground; StartTrial/Subscribe are flushed immediately on top of
/// that. Undelivered events persist on disk and go out on the next launch.
///
/// The access token only authorizes *sending* events for this app — it can't
/// read anything. Like every TikTok/Meta SDK token it ships inside the binary
/// and is extractable from any IPA, so hardcoding it is the industry norm.
enum TikTokEvents {
    private static var configured = false

    private static let accessToken = "TTGg6KgTB13sTba36npjIPENlJncXO9G"
    private static let appStoreID = "6779190323"
    private static let tiktokAppID = "7680177628476751892"

    /// Called from AnalyticsService.configure(), which already gates DEBUG
    /// builds behind "-analytics-debug YES" — owner test runs stay out of the
    /// campaign data. Debug builds report to the Test Events tab only.
    static func configure() {
        guard AnalyticsService.adSDKsEnabled else { return }
        guard let config = TikTokConfig(
            accessToken: accessToken,
            appId: appStoreID,
            tiktokAppId: tiktokAppID
        ) else { return }
        // StartTrial/Subscribe are sent manually with exact values below —
        // the SDK's own StoreKit observer would report the same purchases a
        // second time under its own names.
        config.disablePaymentTracking()
        #if DEBUG
        config.enableDebugMode()
        #endif
        TikTokBusiness.initializeSdk(config)
        configured = true
    }

    /// Fan-out from AnalyticsService.track — one call site, so the PostHog
    /// funnel and the TikTok signals can never drift apart.
    static func forward(_ event: AnalyticsEvent, properties: [String: Any]) {
        guard configured else { return }
        let productID = properties["product"] as? String

        switch event {
        case .onboardingCompleted:
            send("Registration")
        case .paywallShown:
            send("ViewContent", contentID: "paywall")
        case .paywallCTATapped:
            send("Checkout", contentID: productID)
        case .trialStarted:
            guard AnalyticsService.isRealMoney(properties) else { return }
            // A trial hasn't paid anything yet — value 0 keeps TikTok's
            // revenue math honest; the money arrives as Subscribe.
            send("StartTrial", contentID: productID, value: "0", currency: properties["currency"] as? String)
            TikTokBusiness.explicitlyFlush()
        case .subscriptionPurchased, .subscriptionRenewed:
            // Every paid transaction is a Subscribe with its real value — the
            // direct monthly buy, the yearly trial converting on day 3, and
            // each renewal after that.
            guard let price = AnalyticsService.paidAmount(properties) else { return }
            send("Subscribe",
                 contentID: productID,
                 value: String(price),
                 currency: properties["currency"] as? String)
            TikTokBusiness.explicitlyFlush()
        default:
            break
        }
    }

    private static func send(_ name: String, contentID: String? = nil, value: String? = nil, currency: String? = nil) {
        let event = TikTokBaseEvent(eventName: name)
        if let contentID { event.addProperty(withKey: "content_id", value: contentID) }
        if let value { event.addProperty(withKey: "value", value: value) }
        if let currency { event.addProperty(withKey: "currency", value: currency) }
        TikTokBusiness.trackTTEvent(event)
    }
}
