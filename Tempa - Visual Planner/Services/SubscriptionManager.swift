import StoreKit
import Observation

@MainActor
@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var hasIntroOfferEligibility: [String: Bool] = [:]
    private var transactionListener: Task<Void, Error>?

    var isSimulating = false
    var simPlans: [SimPlan] = []

    struct SimPlan: Identifiable {
        let id: String
        let name: String
        let price: String
        let monthlyPrice: String?
        let periodLabel: String
        let hasTrial: Bool
    }

    var isPro: Bool { !purchasedProductIDs.isEmpty }

    /// When the running free trial ends — nil when there is no trial. Home's
    /// first-day card says it out loud, because "I'll forget to cancel" is
    /// the reflex that cancels a trial in its first minute.
    private(set) var trialEndsAt: Date?

    /// True once ANY subscription transaction has ever existed for this Apple ID —
    /// drives the no-trial resubscribe paywall for churned users (trial
    /// eligibility itself is enforced by Apple regardless).
    private(set) var hasEverSubscribed = false

    /// True after the first StoreKit entitlement pass has completed — the root
    /// router waits for this (sub-second, works offline: local receipts).
    private(set) var entitlementsChecked = false

    /// Purchases completed in THIS process, by expiry. Merged into every
    /// entitlement refresh so a lagging currentEntitlements (sandbox does this
    /// right after finish()) can't clobber a subscription we watched the user
    /// buy seconds ago. Entries retire on their own as they expire.
    private var locallyPurchased: [String: Date] = [:]

    private let productIDs = ["tempa_yearly", "tempa_monthly", "tempa_weekly"]

    /// Products with a purchase() call in progress. Transaction.updates can
    /// echo that very purchase before purchase() returns; the paywall reports
    /// it as trial_started / subscription_purchased, so the listener must
    /// leave it alone or Meta counts the sale twice.
    private var inFlightProductIDs: Set<String> = []

    init() {
        transactionListener = startTransactionListener()
        #if DEBUG
        // "-sim-pro YES": open as a subscriber. For looking at the main
        // screens from the command line (simctl), where no StoreKit
        // configuration is attached and the sandbox store asks for an Apple
        // ID. Pair with "-funnelCompletedOnce YES" to skip the owner funnel
        // for that one launch — both live in the argument domain only.
        if UserDefaults.standard.bool(forKey: "sim-pro") { simulatePurchase() }
        #endif
        // Entitlements must not queue behind the product-fetch retry loop —
        // a paying subscriber shouldn't open the app as "free" for 2 seconds.
        Task { [self] in
            await updatePurchasedProducts()
        }
        Task { [self] in
            await ensureProductsLoaded()
        }
    }

    /// Reach StoreKit, retrying a few times — a cold-start race can make the first
    /// call return nothing. Simulation is only a fallback while no real products are
    /// reachable, and it self-heals: call again (e.g. when the paywall appears) and
    /// real products replace the fake ones.
    func ensureProductsLoaded() async {
        guard products.isEmpty else { return }
        for attempt in 1...3 {
            do {
                let loaded = try await Product.products(for: productIDs)
                if !loaded.isEmpty {
                    products = loaded.sorted { p1, p2 in
                        let order = ["tempa_yearly": 0, "tempa_monthly": 1, "tempa_weekly": 2]
                        return (order[p1.id] ?? 3) < (order[p2.id] ?? 3)
                    }
                    isSimulating = false
                    simPlans = []
                    print("[Tempa] StoreKit: loaded \(loaded.count) product(s) — store is live: \(loaded.map(\.id).joined(separator: ", "))")
                    await checkIntroEligibility()
                    return
                }
                print("[Tempa] StoreKit attempt \(attempt): 0 products. Launched from Xcode with the StoreKit configuration selected in the scheme?")
            } catch {
                print("[Tempa] StoreKit attempt \(attempt) failed: \(error.localizedDescription)")
            }
            try? await Task.sleep(for: .milliseconds(600))
        }
        #if DEBUG
        // Dev-only: in Release a store outage must surface the real error on the
        // paywall, never fake plans whose taps grant Pro for free.
        if products.isEmpty && !isSimulating {
            print("[Tempa] StoreKit unreachable → simulation fallback: taps fake-complete the purchase, no payment sheet will appear")
            activateSimulation()
        }
        #endif
    }

    private func activateSimulation() {
        isSimulating = true
        // Dev-only fallback when no StoreKit products are available (no App Store
        // Connect products and no .storekit config selected in the scheme). Real
        // builds show Product.displayPrice — already in the buyer's own currency.
        simPlans = [
            SimPlan(id: "tempa_yearly", name: "Yearly", price: "$29.99", monthlyPrice: "$2.50", periodLabel: "year", hasTrial: true),
            SimPlan(id: "tempa_monthly", name: "Monthly", price: "$4.49", monthlyPrice: nil, periodLabel: "month", hasTrial: false),
            SimPlan(id: "tempa_weekly", name: "Weekly", price: "$1.99", monthlyPrice: nil, periodLabel: "week", hasTrial: false),
        ]
        hasIntroOfferEligibility = ["tempa_yearly": true]
    }

    func simulatePurchase() {
        purchasedProductIDs.insert("tempa_yearly")
        // Survive the entitlement refresh on the next foreground — a
        // simulated buyer must stay "Pro" for the whole test session.
        locallyPurchased["tempa_yearly"] = .distantFuture
        hasEverSubscribed = true
    }

    func checkIntroEligibility() async {
        if isSimulating { return }
        for product in products {
            if let sub = product.subscription {
                // isEligibleForIntroOffer is GROUP-level: it says "this user never
                // used an intro in this group", true even for plans that have no
                // intro offer at all. Require the plan to actually carry one.
                var eligible = false
                let offer = sub.introductoryOffer
                if offer != nil {
                    eligible = await sub.isEligibleForIntroOffer
                }
                hasIntroOfferEligibility[product.id] = eligible
                #if DEBUG
                if offer == nil {
                    print("[Tempa] trial: \(product.id) has NO introductory offer in App Store Connect → no trial UI for anyone")
                } else {
                    print("[Tempa] trial: \(product.id) offers \(offer!.period.value) \(offer!.period.unit) free; this Apple ID eligible: \(eligible)")
                }
                #endif
            }
        }
    }

    func purchase(_ product: Product) async throws -> Transaction? {
        inFlightProductIDs.insert(product.id)
        defer { inFlightProductIDs.remove(product.id) }
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            // RevenueCat observer mode: must see the purchase before finish().
            await RevenueCatService.record(result)
            await transaction.finish()
            // Only now, with the transaction finished, does the ledger take
            // it: a kill between purchase() and finish() re-delivers it
            // through Transaction.updates on the next launch, and THAT copy
            // must still be reportable — the celebration never ran.
            PurchaseSignals.recordOwnedHere(transaction)
            PurchaseSignals.markReported(transaction)
            // currentEntitlements can lag right after finish() — reliably in
            // sandbox, occasionally in production. The verified transaction in
            // hand IS the entitlement: remember it and merge it into every
            // refresh until its expiry, or isPro stays false and the router
            // bounces a fresh subscriber onto the hard paywall.
            if transaction.revocationDate == nil,
               (transaction.expirationDate ?? .distantFuture) > .now {
                locallyPurchased[transaction.productID] =
                    transaction.expirationDate ?? .distantFuture
                hasEverSubscribed = true
            }
            await updatePurchasedProducts()
            return transaction

        case .userCancelled:
            return nil

        case .pending:
            // Ask-to-Buy: a parent still has to approve. Not an error — the
            // Transaction.updates listener completes it whenever they do,
            // and reports it then (the paywall never sees a transaction).
            PurchaseSignals.markPending(product.id)
            return nil

        @unknown default:
            throw SubscriptionError.unknown
        }
    }

    func updatePurchasedProducts() async {
        var purchased: Set<String> = []
        var trialEnd: Date?
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            // Belt and braces: currentEntitlements should only yield active
            // transactions, but check revocation AND expiry explicitly.
            guard transaction.revocationDate == nil,
                  (transaction.expirationDate ?? .distantFuture) > .now else { continue }
            purchased.insert(transaction.productID)
            if PurchaseSignals.isIntroductory(transaction) { trialEnd = transaction.expirationDate }
        }
        trialEndsAt = trialEnd
        locallyPurchased = locallyPurchased.filter { $0.value > .now }
        for id in locallyPurchased.keys { purchased.insert(id) }
        purchasedProductIDs = purchased
        #if DEBUG
        print("[Tempa] entitlements refresh → \(purchased.isEmpty ? "none" : purchased.joined(separator: ", "))")
        #endif

        if !hasEverSubscribed {
            for id in productIDs {
                if let latest = await Transaction.latest(for: id), case .verified = latest {
                    hasEverSubscribed = true
                    break
                }
            }
        }
        entitlementsChecked = true

        // Entitlements just moved (purchase, restore, expiry) — trial
        // eligibility may have moved with them. Fire-and-forget: the purchase
        // path awaits us, and its checkmark must not wait on three more calls.
        Task { await checkIntroEligibility() }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        await updatePurchasedProducts()
    }

    private func startTransactionListener() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? self?.checkVerified(result) {
                    // Known analytics gap: transactions landing here (Ask-to-Buy
                    // approvals, offer codes, interrupted purchases) can't be
                    // recorded with RevenueCat client-side — recordPurchase needs
                    // the Product.PurchaseResult, which never existed on this
                    // path. App Store Server Notifications v2 → RevenueCat covers
                    // them server-side. Entitlements are unaffected either way.
                    await transaction.finish()
                    await self?.updatePurchasedProducts()
                    await self?.reportOutOfBandTransaction(transaction)
                }
            }
        }
    }

    /// The money that never crosses the paywall: the yearly trial converting
    /// on day 3, every renewal after it, an Ask-to-Buy approval. Reported
    /// once per transaction as subscription_renewed (kind: purchase /
    /// trial_converted / renewal) — the ad platforms turn it into revenue,
    /// PostHog into the trial→paid rate.
    ///
    /// Only THIS device's subscriptions count: StoreKit delivers every
    /// renewal to every device on the Apple ID, and the ledger that stops a
    /// double report lives on one device. So a renewal is reported by the
    /// device where the subscription was bought (or Ask-to-Buy'd); a phone
    /// that merely shares the Apple ID stays quiet. Reinstalling the buying
    /// device loses that memory and under-reports — the safe direction for
    /// ad ROAS, and RevenueCat has the server-side truth anyway.
    private func reportOutOfBandTransaction(_ transaction: Transaction) async {
        guard !inFlightProductIDs.contains(transaction.productID),
              transaction.revocationDate == nil else { return }
        // Not the expiry: a renewal that happened while the app was closed
        // for months arrives already expired and is still money that was paid.
        let approvedHere = transaction.originalID == transaction.id
            && PurchaseSignals.isPending(transaction.productID)
        guard approvedHere || PurchaseSignals.isOwnedHere(transaction),
              PurchaseSignals.markReported(transaction) else { return }
        if approvedHere {
            PurchaseSignals.clearPending(transaction.productID)
            PurchaseSignals.recordOwnedHere(transaction)
        }
        // The list price is the fallback for the amount; make sure it exists.
        await ensureProductsLoaded()
        let product = products.first { $0.id == transaction.productID }
        var props = PurchaseSignals.properties(for: transaction, product: product)
        if PurchaseSignals.isIntroductory(transaction) {
            // Only an Ask-to-Buy trial approved after the fact lands here —
            // the paywall reports every other trial start itself.
            AnalyticsService.shared.track(.trialStarted, properties: props)
            return
        }
        props["kind"] = PurchaseSignals.kind(of: transaction)
        AnalyticsService.shared.track(.subscriptionRenewed, properties: props)
    }

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.failedVerification
        case .verified(let value):
            return value
        }
    }
}

/// What analytics may say about a verified StoreKit transaction — and the
/// device-local ledger that makes each sale reported exactly once, whichever
/// path (purchase() result or Transaction.updates) delivers it. Everything
/// lives in UserDefaults: a reinstall forgets it all, which only ever means
/// under-reporting.
enum PurchaseSignals {
    /// Transaction IDs analytics has already reported.
    private static let reportedKey = "analyticsReportedTransactionIDs"
    /// Original transaction IDs of subscriptions bought (or Ask-to-Buy'd)
    /// on this device — the ones whose renewals this device reports.
    private static let ownedKey = "analyticsOwnedOriginalTransactionIDs"
    /// Originals that started as a free trial — their first paid renewal is
    /// the trial converting, not a routine renewal.
    private static let trialKey = "analyticsTrialOriginalTransactionIDs"
    /// Originals whose trial conversion has been reported.
    private static let convertedKey = "analyticsConvertedOriginalTransactionIDs"
    /// Products awaiting an Ask-to-Buy decision from this device.
    private static let pendingKey = "analyticsPendingProductIDs"

    /// Marks the transaction as reported. Returns false when it already was.
    @discardableResult
    static func markReported(_ transaction: Transaction) -> Bool {
        insert(String(transaction.id), into: reportedKey)
    }

    /// A subscription bought on this device: its renewals are ours to report.
    static func recordOwnedHere(_ transaction: Transaction) {
        insert(String(transaction.originalID), into: ownedKey)
        if isIntroductory(transaction) {
            insert(String(transaction.originalID), into: trialKey)
        }
    }

    static func isOwnedHere(_ transaction: Transaction) -> Bool {
        list(ownedKey).contains(String(transaction.originalID))
    }

    static func markPending(_ productID: String) { insert(productID, into: pendingKey) }
    static func isPending(_ productID: String) -> Bool { list(pendingKey).contains(productID) }
    static func clearPending(_ productID: String) {
        UserDefaults.standard.set(list(pendingKey).filter { $0 != productID }, forKey: pendingKey)
    }

    /// "purchase" for a brand-new subscription, "trial_converted" for the
    /// first paid renewal of one that started free, "renewal" otherwise.
    /// Records the conversion, so ask once per transaction.
    static func kind(of transaction: Transaction) -> String {
        if transaction.originalID == transaction.id { return "purchase" }
        let original = String(transaction.originalID)
        if list(trialKey).contains(original), insert(original, into: convertedKey) {
            return "trial_converted"
        }
        return "renewal"
    }

    /// A free-trial transaction — not money.
    static func isIntroductory(_ transaction: Transaction) -> Bool {
        if #available(iOS 17.2, *) {
            return transaction.offer?.type == .introductory
        } else {
            return transaction.offerType == .introductory
        }
    }

    /// The purchase facts every channel receives: product, price, currency,
    /// and the environment — the ad platforms drop anything that isn't
    /// "production". Price is what the transaction itself says was paid
    /// when StoreKit knows it (iOS 17.2+; a promo-code renewal reports the
    /// promo price, a free one 0 — and 0 never reaches an ad platform).
    /// A free trial carries the LIST price of the plan being tried instead:
    /// trial_started has always meant that, and the ad SDKs hard-code the
    /// trial's own value to 0 anyway. The list price is also the fallback
    /// on iOS 17.0–17.1, where the transaction has no price of its own.
    static func properties(for transaction: Transaction, product: Product?) -> [String: Any] {
        var props: [String: Any] = [
            "product": transaction.productID,
            "transaction_id": String(transaction.id),
            "environment": environmentName(transaction),
        ]
        var price: Decimal?
        var currency: String?
        if #available(iOS 17.2, *), !isIntroductory(transaction), let paid = transaction.price {
            price = paid
            currency = transaction.currency?.identifier
        }
        if price == nil, let product {
            price = product.price
            currency = product.priceFormatStyle.currencyCode
        }
        if let price { props["price"] = NSDecimalNumber(decimal: price).doubleValue }
        if let currency { props["currency"] = currency }
        return props
    }

    static func environmentName(_ transaction: Transaction) -> String {
        switch transaction.environment {
        case .production: return "production"
        case .sandbox: return "sandbox"
        case .xcode: return "xcode"
        default: return "unknown"
        }
    }

    // MARK: - Storage

    private static func list(_ key: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    /// Appends when absent; returns false if it was already there. Each list
    /// is capped at 200 — years of renewals — so nothing grows forever.
    @discardableResult
    private static func insert(_ value: String, into key: String) -> Bool {
        var values = list(key)
        if values.contains(value) { return false }
        values.append(value)
        if values.count > 200 { values.removeFirst(values.count - 200) }
        UserDefaults.standard.set(values, forKey: key)
        return true
    }
}

enum SubscriptionError: Error, LocalizedError {
    case failedVerification
    case pending
    case unknown
    case productsNotLoaded

    var errorDescription: String? {
        switch self {
        case .failedVerification: return "Transaction verification failed"
        case .pending: return "Purchase is pending approval"
        case .unknown: return "An unknown error occurred"
        case .productsNotLoaded: return "Products not yet loaded"
        }
    }
}
