import Testing
import Foundation
@testable import Tempa___Visual_Planner

/// A task reminder opens with the emoji twin of the icon on the task's card,
/// so the lock screen says what's coming before a word of it is read.
@MainActor
struct TaskReminderEmojiTests {
    @Test func everyIconTheAICanPickHasAnEmoji() {
        let vocabulary = ClaudeAPIClient.iconVocabulary
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(!vocabulary.isEmpty)
        for icon in vocabulary {
            #expect(TaskNotifications.emojiByIcon[icon] != nil, "no emoji for \(icon)")
        }
    }

    @Test func aPlaceholderIconFallsBackToTheCategorysOwn() {
        for (category, _) in Cat.all {
            let emoji = TaskNotifications.emoji(icon: "circle", category: category)
            #expect(emoji != nil, "no emoji for \(category)")
            #expect(emoji == TaskNotifications.emojiByIcon[Cat.icon(for: category)])
        }
    }

    /// 🗑 and friends draw as a flat black glyph unless U+FE0F follows them.
    @Test func everyEmojiDrawsInColour() {
        for (icon, emoji) in TaskNotifications.emojiByIcon {
            let scalars = emoji.unicodeScalars
            let inColour = scalars.first!.properties.isEmojiPresentation || scalars.contains("\u{FE0F}")
            #expect(inColour, "\(icon) → \(emoji)")
            #expect(emoji.count == 1, "\(icon) → \(emoji)")
        }
    }

    @Test func theTitleLeadsWithTheEmoji() {
        #expect(TaskNotifications.reminderTitle("Take vitamin D", icon: "pills", category: "health") == "💊 Take vitamin D")
        #expect(TaskNotifications.reminderTitle("Подзвонити мамі", icon: "circle", category: "social") == "📞 Подзвонити мамі")
        #expect(TaskNotifications.reminderTitle("3 pm standup", icon: "laptopcomputer", category: "work") == "💻 3 pm standup")
    }

    @Test func theUsersOwnEmojiIsNotDoubled() {
        #expect(TaskNotifications.reminderTitle("🎂 Mom's birthday", icon: "phone", category: "social") == "🎂 Mom's birthday")
        #expect(TaskNotifications.reminderTitle("✉️ Reply to Ola", icon: "envelope", category: "work") == "✉️ Reply to Ola")
    }

    @Test func nothingToGoOnLeavesTheTitleAlone() {
        #expect(TaskNotifications.reminderTitle("Something", icon: nil, category: nil) == "Something")
    }
}
