import Foundation
import Security

/// God mode for the owner's own phone — and NOBODY else's.
///
/// How the nail gets hammered in: every DEBUG launch plants a token in the
/// device Keychain. Keychain outlives app deletion, so ANY later build of
/// the app on this same device — TestFlight and App Store included — sees
/// the token and keeps god mode on. A phone that has never run a DEBUG
/// build can never activate it: Release code contains no code path that
/// plants the token, only one that looks for it. Production users therefore
/// always get the standard product logic.
///
/// If a future iOS ever clears Keychain on uninstall, one Debug run from
/// Xcode replants the nail.
enum OwnerMode {
    private static let service = "tempa.owner-mode"
    private static let account = "owner"

    static let isActive: Bool = {
        #if DEBUG
        plantToken()
        return true
        #else
        return tokenExists()
        #endif
    }()

    /// True while the owner's test cycle is playing a brand-new user:
    /// god mode on and the funnel not yet completed on this install.
    /// Drives the forced funnel (RootView) and the always-visible trial
    /// timeline (PaywallView).
    static var playingNewUser: Bool {
        isActive && !UserDefaults.standard.bool(forKey: "funnelCompletedOnce")
    }

    private static func tokenExists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    #if DEBUG
    private static func plantToken() {
        guard !tokenExists() else { return }
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Readable from a cold launch as soon as the phone has been
            // unlocked once since boot — god mode must not flicker off.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data("god".utf8),
        ]
        SecItemAdd(attrs as CFDictionary, nil)
        print("[Tempa] OwnerMode: nail planted — this device keeps god mode in ALL future builds")
    }
    #endif
}
