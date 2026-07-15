import Foundation

/// In-app language override. `.system` follows the device language; any other
/// case forces the app (and voice input) into that language on the next launch
/// via the standard AppleLanguages override.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, de, uk, es, fr, pt, nb, fi, nl
    var id: String { rawValue }

    /// Native names on purpose — every user should recognise their own language.
    var displayName: String {
        switch self {
        case .system: String(localized: "System")
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

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "system") ?? .system
    }

    /// Persist the choice and set/clear the launch-time language override.
    func apply() {
        UserDefaults.standard.set(rawValue, forKey: "appLanguage")
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }
}
