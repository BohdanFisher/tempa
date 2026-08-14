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
    /// The language comes from the pick, but region and hour cycle stay the
    /// DEVICE's: Europe keeps its 24-hour clock even in English UI, the US
    /// keeps AM/PM, and the user's own 24-Hour Time toggle is honoured.
    var locale: Locale {
        // .system can't use autoupdatingCurrent: after an in-app switch it
        // stays frozen to the LAUNCH language until relaunch. Rebuild from the
        // device's live preference list instead.
        let identifier = self == .system
            ? (Locale.preferredLanguages.first ?? Locale.current.identifier)
            : rawValue
        var comps = Locale.Components(identifier: identifier)
        if comps.region == nil { comps.region = Locale.current.region }
        comps.hourCycle = Locale.current.hourCycle
        return Locale(components: comps)
    }

    /// The language code actually in effect — the pick, or the device's
    /// first preferred language when following the system.
    var effectiveCode: String {
        guard self == .system else { return rawValue }
        let device = Locale.preferredLanguages.first ?? "en"
        return Locale(identifier: device).language.languageCode?.identifier ?? "en"
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
        // Always resolve to a concrete code — "system" itself has no .lproj,
        // and the frozen main bundle would keep serving the launch language.
        Bundle.applyLanguageOverride(effectiveCode)
    }
}

// MARK: - Live bundle override

private var overridePathKey: UInt8 = 0

/// Routes Bundle.main string lookups into the selected language's .lproj so a
/// language change takes effect immediately — no relaunch required.
private final class LanguageOverrideBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if objc_getAssociatedObject(self, &overridePathKey) != nil {
            let target = Bundle.appLanguage
            if target !== self {
                return target.localizedString(forKey: key, value: value, table: tableName)
            }
            // Source-language fallback: the key IS the English string.
            if let value, !value.isEmpty { return value }
            return key
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// The bundle serving the currently selected app language — pass this to
    /// String(localized:bundle:) so strings switch instantly on language change.
    /// (On modern iOS, String(localized:) bypasses the swizzled lookup.)
    /// A bundle with NO string tables at all: every String(localized:bundle:)
    /// lookup against it returns the key itself — i.e. the English source
    /// text. This is how "English" works without an en.lproj on disk (English
    /// is the catalog's source language and never ships as an .lproj).
    private static let sourceLanguageFallback: Bundle = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tempa-source-language.bundle", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return Bundle(url: dir) ?? .main
    }()

    static var appLanguage: Bundle {
        guard let code = objc_getAssociatedObject(Bundle.main, &overridePathKey) as? String else {
            return .main
        }
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return sourceLanguageFallback
    }

    static func applyLanguageOverride(_ code: String?) {
        if object_getClass(Bundle.main) != LanguageOverrideBundle.self {
            object_setClass(Bundle.main, LanguageOverrideBundle.self)
        }
        objc_setAssociatedObject(Bundle.main, &overridePathKey, code, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
