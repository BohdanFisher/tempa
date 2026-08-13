import Foundation
import NaturalLanguage

/// The language a task was WRITTEN in — which is what AI answers must follow.
/// Deliberately not the app language and not the device language: someone with
/// a Ukrainian interface still gets English steps for an English task.
enum TaskLanguage {
    /// Anything shorter than this is too weak a signal to trust.
    private static let minimumConfidence = 0.6

    /// BCP-47 code ("en", "uk", "de"), or nil when the text is too short or
    /// ambiguous to call — in that case we say nothing and let the model read
    /// the task itself rather than pin it to a wrong guess.
    static func detect(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let dominant = recognizer.dominantLanguage, dominant != .undetermined else { return nil }
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[dominant] ?? 0
        guard confidence >= minimumConfidence else { return nil }
        return dominant.rawValue
    }

    /// English name of the language — models follow "Ukrainian" far more
    /// reliably than a bare "uk".
    static func englishName(for code: String) -> String {
        Locale(identifier: "en_US").localizedString(forLanguageCode: code) ?? code
    }

    /// Line appended to the user message so the output language is stated
    /// outright instead of inferred from a two-word task.
    static func outputDirective(for text: String) -> String? {
        guard let code = detect(text) else { return nil }
        return "OUTPUT LANGUAGE: \(englishName(for: code)). Every human-readable value you "
            + "return must be written in this language, whatever language these instructions use."
    }
}

extension Bundle {
    /// Bundle for a specific language code, for text that must follow the
    /// task's language rather than the app's. Falls back to the app language.
    static func forLanguage(_ code: String?) -> Bundle {
        guard let code,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .appLanguage }
        return bundle
    }
}
