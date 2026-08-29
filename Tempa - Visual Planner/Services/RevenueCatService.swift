import Foundation
import StoreKit
import RevenueCat

/// RevenueCat in OBSERVER mode: our own StoreKit 2 code stays the single owner
/// of purchases and entitlements; RevenueCat only receives the events — for the
/// revenue dashboards (MRR, trials, churn) and, later, paywall experiments.
enum RevenueCatService {
    /// PUBLIC SDK key for the "Tempa (App Store)" app — public by design,
    /// RevenueCat explicitly documents it as safe to ship in the binary.
    /// Dashboard: project f9f86191, entitlement "Tempa Pro".
    private static let apiKey = "appl_btXekHTbffdqmWcqDBGgYKySwPF"

    /// Call once, before any purchase can happen.
    static func configure() {
        Purchases.logLevel = .warn
        Purchases.configure(
            with: .builder(withAPIKey: apiKey)
                // .myApp = observer mode: we complete purchases ourselves.
                .with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
                // Analytics calls must fail fast — never at Apple's default pace.
                .with(networkTimeout: 10)
                .build()
        )
    }

    /// StoreKit 2 observer mode contract: hand RevenueCat the raw purchase
    /// result BEFORE the transaction is finished, or it never sees the sale.
    /// Failures are swallowed and the wait is BOUNDED — the user has already
    /// paid, and a RevenueCat outage must not hold the success screen hostage.
    /// A cancel()-based deadline is NOT a bound here: recordPurchase ignores
    /// task cancellation, so the await would ride out the SDK's own retries.
    /// Race it against a real timer instead — first finisher resumes the
    /// caller, a late recordPurchase still completes in the background.
    static func record(_ result: Product.PurchaseResult) async {
        final class Once: @unchecked Sendable {
            private let lock = NSLock()
            private var resumed = false
            func claim() -> Bool {
                lock.lock(); defer { lock.unlock() }
                if resumed { return false }
                resumed = true
                return true
            }
        }
        let once = Once()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            Task {
                _ = try? await Purchases.shared.recordPurchase(result)
                if once.claim() { cont.resume() }
            }
            Task {
                try? await Task.sleep(for: .seconds(3))
                if once.claim() { cont.resume() }
            }
        }
    }
}
