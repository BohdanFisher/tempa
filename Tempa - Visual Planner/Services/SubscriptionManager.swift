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

    /// True once ANY subscription transaction has ever existed for this Apple ID —
    /// drives the no-trial resubscribe paywall for churned users (trial
    /// eligibility itself is enforced by Apple regardless).
    private(set) var hasEverSubscribed = false

    private let productIDs = ["tempa_yearly", "tempa_monthly", "tempa_weekly"]

    init() {
        transactionListener = startTransactionListener()
        Task { [self] in
            await ensureProductsLoaded()
            await updatePurchasedProducts()
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
        if products.isEmpty && !isSimulating {
            print("[Tempa] StoreKit unreachable → simulation fallback: taps fake-complete the purchase, no payment sheet will appear")
            activateSimulation()
        }
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
        hasEverSubscribed = true
    }

    func checkIntroEligibility() async {
        if isSimulating { return }
        for product in products {
            if let sub = product.subscription {
                let eligible = await sub.isEligibleForIntroOffer
                hasIntroOfferEligibility[product.id] = eligible
            }
        }
    }

    func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await updatePurchasedProducts()
            return transaction

        case .userCancelled:
            return nil

        case .pending:
            // Ask-to-Buy: a parent still has to approve. Not an error — the
            // Transaction.updates listener completes it whenever they do.
            return nil

        @unknown default:
            throw SubscriptionError.unknown
        }
    }

    func updatePurchasedProducts() async {
        var purchased: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            // Belt and braces: currentEntitlements should only yield active
            // transactions, but check revocation AND expiry explicitly.
            guard transaction.revocationDate == nil,
                  (transaction.expirationDate ?? .distantFuture) > .now else { continue }
            purchased.insert(transaction.productID)
        }
        purchasedProductIDs = purchased

        if !hasEverSubscribed {
            for id in productIDs {
                if let latest = await Transaction.latest(for: id), case .verified = latest {
                    hasEverSubscribed = true
                    break
                }
            }
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        await updatePurchasedProducts()
    }

    private func startTransactionListener() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? self?.checkVerified(result) {
                    await transaction.finish()
                    await self?.updatePurchasedProducts()
                }
            }
        }
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
