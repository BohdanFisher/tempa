import XCTest
import StoreKit
import StoreKitTest
@testable import Tempa___Visual_Planner

/// The one rule that must never break: backing out of Apple's payment sheet
/// grants NOTHING. Pro exists only for an Apple ID with a live, verified
/// entitlement — never for a cancelled, failed or pending purchase.
final class PaywallAccessTests: XCTestCase {
    private var session: SKTestSession!

    override func setUpWithError() throws {
        session = try SKTestSession(configurationFileNamed: "TempaStoreKit")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
    }

    override func tearDownWithError() throws {
        session = nil
    }

    @MainActor
    func testCancelledPaymentSheetGrantsNothing() async throws {
        let products = try await Product.products(for: ["tempa_yearly"])
        let yearly = try XCTUnwrap(products.first)
        let manager = SubscriptionManager()
        await manager.updatePurchasedProducts()
        XCTAssertFalse(manager.isPro, "A fresh install must start locked")

        // The user backs out of Apple's sheet.
        session.failTransactionsEnabled = true
        session.failureError = .paymentCancelled

        let transaction = try? await manager.purchase(yearly)
        XCTAssertNil(transaction, "A cancelled purchase must not hand back a transaction")

        // This is exactly what the paywall does after a nil result.
        await manager.updatePurchasedProducts()
        XCTAssertFalse(manager.isPro, "Cancelling the payment sheet must not unlock Pro")

        var entitled = false
        for await entitlement in Transaction.currentEntitlements {
            if (try? entitlement.payloadValue) != nil { entitled = true }
        }
        XCTAssertFalse(entitled, "StoreKit must hold no entitlement after a cancel")
    }

    @MainActor
    func testRealPurchaseUnlocksPro() async throws {
        let products = try await Product.products(for: ["tempa_yearly"])
        let yearly = try XCTUnwrap(products.first)
        let manager = SubscriptionManager()

        let transaction = try await manager.purchase(yearly)
        XCTAssertNotNil(transaction)
        XCTAssertTrue(manager.isPro, "A verified purchase unlocks Pro — the control case")
    }
}
