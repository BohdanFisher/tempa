import Foundation
#if DEBUG && canImport(StoreKitTest)
import StoreKitTest
#endif

/// Debug-only: boots the local StoreKit test store straight from the bundled
/// TempaStoreKit.storekit, so test purchases work regardless of what the Xcode
/// scheme has (or hasn't) selected. Compiles to a no-op in Release, and the
/// framework is weak-linked — a device without the developer runtime just
/// skips it gracefully.
enum DebugStoreKit {
    static func activate() {
        #if DEBUG && canImport(StoreKitTest)
        guard NSClassFromString("SKTestSession") != nil else {
            print("[Tempa] Debug StoreKit: StoreKitTest runtime not present — relying on the scheme's config")
            return
        }
        guard SessionHolder.session == nil else { return }
        guard let url = Bundle.main.url(forResource: "TempaStoreKit", withExtension: "storekit") else {
            print("[Tempa] Debug StoreKit: bundled TempaStoreKit.storekit not found")
            return
        }
        print("[Tempa] Debug StoreKit: starting test session… (if no follow-up line appears, session init is hanging)")
        do {
            let session = try SKTestSession(contentsOf: url)
            SessionHolder.session = session
            print("[Tempa] Debug StoreKit: local test store ACTIVE from bundled config — scheme selection not required")
        } catch {
            print("[Tempa] Debug StoreKit: failed to start test session — \(error.localizedDescription)")
        }
        #endif
    }
}

#if DEBUG && canImport(StoreKitTest)
/// Keeps the test session alive for the whole app run — letting it deallocate
/// would tear the test store down again.
private enum SessionHolder {
    static var session: SKTestSession?
}
#endif
