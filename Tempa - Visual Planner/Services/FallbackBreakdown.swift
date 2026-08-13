import Foundation

/// Offline stand-in for the AI breakdown — used when the API is unreachable or
/// the free daily quota is spent. Speaks the language the task was written in,
/// same as the real breakdown does.
enum FallbackBreakdown {
    static func generate(for taskTitle: String) -> TaskBreakdown {
        let b = Bundle.forLanguage(TaskLanguage.detect(taskTitle))

        if matches(taskTitle, Keywords.cleaning) {
            return TaskBreakdown(steps: [
                .init(title: String(localized: "Gather scattered items into one pile", bundle: b), duration: 5, icon: "bag"),
                .init(title: String(localized: "Wipe down surfaces", bundle: b), duration: 10, icon: "sparkles"),
                .init(title: String(localized: "Vacuum or sweep the floor", bundle: b), duration: 15, icon: "leaf"),
                .init(title: String(localized: "Take out the trash", bundle: b), duration: 5, icon: "trash")
            ])
        }

        if matches(taskTitle, Keywords.writing) {
            return TaskBreakdown(steps: [
                .init(title: String(localized: "Open document or email", bundle: b), duration: 2, icon: "doc.text"),
                .init(title: String(localized: "Draft main points", bundle: b), duration: 10, icon: "doc.text"),
                .init(title: String(localized: "Review what you wrote", bundle: b), duration: 5, icon: "doc.text"),
                .init(title: String(localized: "Send it off", bundle: b), duration: 1, icon: "envelope")
            ])
        }

        if matches(taskTitle, Keywords.studying) {
            return TaskBreakdown(steps: [
                .init(title: String(localized: "Set up your workspace", bundle: b), duration: 3, icon: "laptopcomputer"),
                .init(title: String(localized: "Read the first section", bundle: b), duration: 20, icon: "book"),
                .init(title: String(localized: "Take a short break", bundle: b), duration: 5, icon: "figure.walk"),
                .init(title: String(localized: "Continue with the next part", bundle: b), duration: 20, icon: "book")
            ])
        }

        if matches(taskTitle, Keywords.cooking) {
            return TaskBreakdown(steps: [
                .init(title: String(localized: "Pick a recipe or decide what to make", bundle: b), duration: 3, icon: "doc.text"),
                .init(title: String(localized: "Gather ingredients", bundle: b), duration: 5, icon: "cart"),
                .init(title: String(localized: "Prep — chop, measure, lay things out", bundle: b), duration: 10, icon: "fork.knife"),
                .init(title: String(localized: "Cook it", bundle: b), duration: 20, icon: "fork.knife"),
                .init(title: String(localized: "Plate and enjoy", bundle: b), duration: 5, icon: "fork.knife")
            ])
        }

        if matches(taskTitle, Keywords.exercise) {
            return TaskBreakdown(steps: [
                .init(title: String(localized: "Put on workout clothes", bundle: b), duration: 3, icon: "figure.walk"),
                .init(title: String(localized: "Warm up gently", bundle: b), duration: 5, icon: "figure.walk"),
                .init(title: String(localized: "Do the main activity", bundle: b), duration: 20, icon: "figure.walk"),
                .init(title: String(localized: "Cool down and stretch", bundle: b), duration: 5, icon: "figure.walk")
            ])
        }

        return TaskBreakdown(steps: [
            .init(title: String(localized: "Set a timer for 15 minutes", bundle: b), duration: 1, icon: "alarm"),
            .init(title: String(localized: "Start anywhere — the hardest part is beginning", bundle: b), duration: 15, icon: "sparkles"),
            .init(title: String(localized: "Pause when the timer ends", bundle: b), duration: 1, icon: "alarm"),
            .init(title: String(localized: "Decide if you want to keep going", bundle: b), duration: 1, icon: "doc.text")
        ])
    }

    /// Word-prefix match, so "cleaning the kitchen" hits "clean" but "залишити"
    /// never hits a stem it merely starts with by accident.
    private static func matches(_ title: String, _ stems: [String]) -> Bool {
        let words = title.lowercased().split { !$0.isLetter }.map(String.init)
        return words.contains { word in stems.contains { word.hasPrefix($0) } }
    }

    /// Stems across the nine languages the app ships in — the offline path
    /// should recognise a German task as well as an English one.
    private enum Keywords {
        static let cleaning = ["clean", "tidy", "room", "apartment", "прибир", "прибрат", "кімнат", "квартир",
                               "putz", "aufräum", "wohnung", "limpi", "habitación", "ménage", "nettoy", "ranger",
                               "arrum", "rydde", "vaske", "siivo", "schoonmaak", "opruim"]
        static let writing = ["email", "write", "report", "mail", "лист", "напис", "звіт", "schreib", "bericht",
                              "escrib", "correo", "informe", "écri", "courriel", "rapport", "escrev", "relatóri",
                              "skriv", "kirjoit", "sähköpost", "schrijv"]
        static let studying = ["study", "read", "learn", "вчит", "вивч", "читат", "навчан", "lern", "lesen",
                               "estudi", "étudi", "lire", "leia", "lese", "studer", "opiskel", "leren", "lezen"]
        static let cooking = ["cook", "meal", "dinner", "lunch", "готув", "вечер", "обід", "koch", "abendessen",
                              "cocin", "cena", "cuisin", "dîner", "cozinh", "jantar", "middag", "ruoka", "ruoan",
                              "koken", "avondeten"]
        static let exercise = ["exercise", "workout", "gym", "run", "jog", "тренув", "спортзал", "біга", "пробіж",
                               "sport", "lauf", "ejercici", "correr", "courir", "trein", "løp", "trene", "juoks",
                               "treeni", "hardlop"]
    }
}
