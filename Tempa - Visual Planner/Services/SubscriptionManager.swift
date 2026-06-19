import StoreKit
import Observation

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

    private let productIDs = ["tempa_yearly", "tempa_monthly", "tempa_weekly"]

    init() {
        transactionListener = startTransactionListener()
        Task { [self] in
            do {
                try await loadProducts()
            } catch {
                activateSimulation()
            }
            await updatePurchasedProducts()
            await checkIntroEligibility()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    func loadProducts() async throws {
        let loaded = try await Product.products(for: productIDs)
        if loaded.isEmpty {
            activateSimulation()
            return
        }
        products = loaded.sorted { p1, p2 in
            let order = ["tempa_yearly": 0, "tempa_monthly": 1, "tempa_weekly": 2]
            return (order[p1.id] ?? 3) < (order[p2.id] ?? 3)
        }
    }

    private func activateSimulation() {
        isSimulating = true
        simPlans = [
            SimPlan(id: "tempa_yearly", name: "Yearly", price: "€29.99", monthlyPrice: "€2.50", periodLabel: "year", hasTrial: true),
            SimPlan(id: "tempa_monthly", name: "Monthly", price: "€4.49", monthlyPrice: nil, periodLabel: "month", hasTrial: false),
            SimPlan(id: "tempa_weekly", name: "Weekly", price: "€1.99", monthlyPrice: nil, periodLabel: "week", hasTrial: false),
        ]
        hasIntroOfferEligibility = ["tempa_yearly": true]
    }

    func simulatePurchase() {
        purchasedProductIDs.insert("tempa_yearly")
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
            throw SubscriptionError.pending

        @unknown default:
            throw SubscriptionError.unknown
        }
    }

    func updatePurchasedProducts() async {
        var purchased: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                if transaction.revocationDate == nil {
                    purchased.insert(transaction.productID)
                }
            }
        }
        purchasedProductIDs = purchased
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

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
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
