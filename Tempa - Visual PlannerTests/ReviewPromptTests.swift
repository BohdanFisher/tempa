import Testing
import CoreData
@testable import Tempa___Visual_Planner

/// The rating ask has exactly one trigger: the first task the person creates
/// themselves in the main app (which is only reachable after a trial or a
/// purchase). Nothing written FOR them — the onboarding demo plan — may count.
@MainActor
struct ReviewPromptTests {
    private static let askedKey = "reviewPromptAskedAfterFirstTask"

    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).container.viewContext
    }

    private func insertTask(into context: NSManagedObjectContext) throws {
        let task = TaskBlock(context: context)
        task.id = UUID()
        task.title = "Call mom"
        task.startTime = Date()
        task.durationMinutes = 15
        task.createdAt = Date()
        try context.save()
    }

    @Test func firstUserTaskTriggersTheAsk() throws {
        UserDefaults.standard.removeObject(forKey: Self.askedKey)
        defer { UserDefaults.standard.removeObject(forKey: Self.askedKey) }

        let context = makeContext()
        let prompt = ReviewPrompt()
        prompt.startObserving(context)
        #expect(prompt.shouldAsk == false)

        try insertTask(into: context)
        #expect(prompt.shouldAsk == true)
    }

    @Test func demoPlanNeverCountsAsFirstTask() throws {
        UserDefaults.standard.removeObject(forKey: Self.askedKey)
        defer { UserDefaults.standard.removeObject(forKey: Self.askedKey) }

        let context = makeContext()
        let prompt = ReviewPrompt()
        prompt.startObserving(context)

        ReviewPrompt.isWritingDemoPlan = true
        try insertTask(into: context)
        ReviewPrompt.isWritingDemoPlan = false
        #expect(prompt.shouldAsk == false)

        // The person's own first task, right after, still gets its moment.
        try insertTask(into: context)
        #expect(prompt.shouldAsk == true)
    }

    @Test func asksOnlyOncePerInstall() throws {
        UserDefaults.standard.removeObject(forKey: Self.askedKey)
        defer { UserDefaults.standard.removeObject(forKey: Self.askedKey) }

        let context = makeContext()
        let prompt = ReviewPrompt()
        prompt.startObserving(context)
        try insertTask(into: context)
        prompt.markAsked()
        #expect(prompt.shouldAsk == false)

        try insertTask(into: context)
        #expect(prompt.shouldAsk == false)

        // A fresh launch on the same install must not start listening again.
        let relaunched = ReviewPrompt()
        relaunched.startObserving(context)
        try insertTask(into: context)
        #expect(relaunched.shouldAsk == false)
    }

    /// Installs that went through the old onboarding carry the retired flag;
    /// it must not silence the ask under the rotated key.
    @Test func oldOnboardingFlagDoesNotSuppressTheAsk() throws {
        UserDefaults.standard.set(true, forKey: "reviewPromptAsked")
        UserDefaults.standard.removeObject(forKey: Self.askedKey)
        defer {
            UserDefaults.standard.removeObject(forKey: "reviewPromptAsked")
            UserDefaults.standard.removeObject(forKey: Self.askedKey)
        }

        let context = makeContext()
        let prompt = ReviewPrompt()
        prompt.startObserving(context)
        try insertTask(into: context)
        #expect(prompt.shouldAsk == true)
    }
}
