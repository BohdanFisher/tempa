import XCTest
import StoreKit
import StoreKitTest

/// Proves the local StoreKit test store works end-to-end: the .storekit config
/// parses at RUNTIME (the Xcode editor is more lenient), both subscriptions load,
/// the yearly trial is intact, and a purchase actually completes.
final class StoreKitConfigTests: XCTestCase {

    // Keep the session alive for the whole test — deallocating it tears the
    // test store down again.
    private var session: SKTestSession!

    override func setUpWithError() throws {
        // Load the repo's config file directly by path so the test never depends
        // on bundle membership.
        session = try SKTestSession(configurationFileNamed: "TempaStoreKit")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
    }

    override func tearDownWithError() throws {
        session = nil
    }

    func testProductsLoadFromConfig() async throws {

        let products = try await Product.products(for: ["tempa_yearly", "tempa_monthly", "tempa_weekly"])
        XCTAssertEqual(products.count, 2, "Both test subscriptions should load (weekly intentionally absent)")

        let yearly = try XCTUnwrap(products.first { $0.id == "tempa_yearly" })
        XCTAssertEqual(yearly.subscription?.subscriptionPeriod.unit, .year)
        let intro = try XCTUnwrap(yearly.subscription?.introductoryOffer, "Yearly must carry the 3-day trial")
        XCTAssertEqual(intro.paymentMode, .freeTrial)
        XCTAssertEqual(intro.period.unit, .day)
        XCTAssertEqual(intro.period.value, 3)

        let monthly = try XCTUnwrap(products.first { $0.id == "tempa_monthly" })
        XCTAssertEqual(monthly.subscription?.subscriptionPeriod.unit, .month)
        XCTAssertNil(monthly.subscription?.introductoryOffer)
    }

    func testYearlyPurchaseSucceeds() async throws {
        let products = try await Product.products(for: ["tempa_yearly"])
        let yearly = try XCTUnwrap(products.first)

        let result = try await yearly.purchase()
        guard case .success(let verification) = result else {
            XCTFail("Purchase did not succeed: \(result)")
            return
        }
        let tx = try verification.payloadValue
        XCTAssertEqual(tx.productID, "tempa_yearly")
        await tx.finish()

        var entitled = false
        for await entitlement in Transaction.currentEntitlements {
            if let t = try? entitlement.payloadValue, t.productID == "tempa_yearly" { entitled = true }
        }
        XCTAssertTrue(entitled, "Purchase should grant the yearly entitlement")
    }
}
