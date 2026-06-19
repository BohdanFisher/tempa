import Foundation

enum FallbackBreakdown {
    static func generate(for taskTitle: String) -> TaskBreakdown {
        let lowered = taskTitle.lowercased()

        if lowered.contains("clean") || lowered.contains("tidy") || lowered.contains("room") || lowered.contains("apartment") {
            return TaskBreakdown(steps: [
                .init(title: "Gather scattered items into one pile", duration: 5, icon: "bag"),
                .init(title: "Wipe down surfaces", duration: 10, icon: "sparkles"),
                .init(title: "Vacuum or sweep the floor", duration: 15, icon: "leaf"),
                .init(title: "Take out the trash", duration: 5, icon: "trash")
            ])
        }

        if lowered.contains("email") || lowered.contains("write") || lowered.contains("report") {
            return TaskBreakdown(steps: [
                .init(title: "Open document or email", duration: 2, icon: "doc.text"),
                .init(title: "Draft main points", duration: 10, icon: "doc.text"),
                .init(title: "Review what you wrote", duration: 5, icon: "doc.text"),
                .init(title: "Send it off", duration: 1, icon: "envelope")
            ])
        }

        if lowered.contains("study") || lowered.contains("read") || lowered.contains("learn") {
            return TaskBreakdown(steps: [
                .init(title: "Set up your workspace", duration: 3, icon: "laptopcomputer"),
                .init(title: "Read the first section", duration: 20, icon: "book"),
                .init(title: "Take a short break", duration: 5, icon: "figure.walk"),
                .init(title: "Continue with the next part", duration: 20, icon: "book")
            ])
        }

        if lowered.contains("cook") || lowered.contains("meal") || lowered.contains("dinner") || lowered.contains("lunch") {
            return TaskBreakdown(steps: [
                .init(title: "Pick a recipe or decide what to make", duration: 3, icon: "doc.text"),
                .init(title: "Gather ingredients", duration: 5, icon: "cart"),
                .init(title: "Prep — chop, measure, lay things out", duration: 10, icon: "fork.knife"),
                .init(title: "Cook it", duration: 20, icon: "fork.knife"),
                .init(title: "Plate and enjoy", duration: 5, icon: "fork.knife")
            ])
        }

        if lowered.contains("exercise") || lowered.contains("workout") || lowered.contains("gym") || lowered.contains("run") {
            return TaskBreakdown(steps: [
                .init(title: "Put on workout clothes", duration: 3, icon: "figure.walk"),
                .init(title: "Warm up gently", duration: 5, icon: "figure.walk"),
                .init(title: "Do the main activity", duration: 20, icon: "figure.walk"),
                .init(title: "Cool down and stretch", duration: 5, icon: "figure.walk")
            ])
        }

        return TaskBreakdown(steps: [
            .init(title: "Set a timer for 15 minutes", duration: 1, icon: "alarm"),
            .init(title: "Start anywhere — the hardest part is beginning", duration: 15, icon: "sparkles"),
            .init(title: "Pause when the timer ends", duration: 1, icon: "alarm"),
            .init(title: "Decide if you want to keep going", duration: 1, icon: "doc.text")
        ])
    }
}
