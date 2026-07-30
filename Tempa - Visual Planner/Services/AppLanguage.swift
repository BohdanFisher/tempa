import Foundation
import ObjectiveC

/// In-app language override. `.system` follows the device language; any other
/// case forces the app (and voice input) into that language on the next launch
/// via the standard AppleLanguages override.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, de, uk, es, fr, pt, nb, fi, nl
    var id: String { rawValue }

    /// Native names on purpose — every user should recognise their own language.
    var displayName: String {
        switch self {
        case .system: String(localized: "System", bundle: .appLanguage)
        case .en: "English"
        case .de: "Deutsch"
        case .uk: "Українська"
        case .es: "Español"
        case .fr: "Français"
        case .pt: "Português"
        case .nb: "Norsk"
        case .fi: "Suomi"
        case .nl: "Nederlands"
        }
    }

    /// Locale for speech recognition — voice input follows the app language.
    var speechLocale: String {
        switch self {
        case .system:
            let code = Locale.current.language.languageCode?.identifier ?? "en"
            return (AppLanguage(rawValue: code) ?? .en).speechLocale
        case .en: return "en-US"
        case .de: return "de-DE"
        case .uk: return "uk-UA"
        case .es: return "es-ES"
        case .fr: return "fr-FR"
        case .pt: return "pt-BR"
        case .nb: return "nb-NO"
        case .fi: return "fi-FI"
        case .nl: return "nl-NL"
        }
    }

    /// Locale matching the selection — lets date formatters switch live too.
    var locale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "system") ?? .system
    }

    /// Persist the choice, keep the launch-time override in sync, and swap the
    /// live string bundle — the change is visible immediately, no relaunch.
    func apply() {
        UserDefaults.standard.set(rawValue, forKey: "appLanguage")
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
        Bundle.applyLanguageOverride(self == .system ? nil : rawValue)
    }
}

// MARK: - Live bundle override

private var overridePathKey: UInt8 = 0

/// Routes Bundle.main string lookups into the selected language's .lproj so a
/// language change takes effect immediately — no relaunch required.
private final class LanguageOverrideBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let path = objc_getAssociatedObject(self, &overridePathKey) as? String,
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// The bundle serving the currently selected app language — pass this to
    /// String(localized:bundle:) so strings switch instantly on language change.
    /// (On modern iOS, String(localized:) bypasses the swizzled lookup.)
    static var appLanguage: Bundle {
        if let path = objc_getAssociatedObject(Bundle.main, &overridePathKey) as? String,
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    static func applyLanguageOverride(_ code: String?) {
        if object_getClass(Bundle.main) != LanguageOverrideBundle.self {
            object_setClass(Bundle.main, LanguageOverrideBundle.self)
        }
        let path = code.flatMap { Bundle.main.path(forResource: $0, ofType: "lproj") }
        objc_setAssociatedObject(Bundle.main, &overridePathKey, path, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
