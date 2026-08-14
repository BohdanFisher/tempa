import CoreData
import CloudKit

struct PersistenceController: Sendable {
    static let shared = PersistenceController()

    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        let now = Date()
        let calendar = Calendar.current

        for i in 0..<5 {
            let task = TaskBlock(context: context)
            task.id = UUID()
            task.title = ["Morning stretch", "Check emails", "Deep work block", "Lunch break", "Review notes"][i]
            task.iconName = ["figure.walk", "envelope", "laptopcomputer", "fork.knife", "doc.text"][i]
            task.colorHex = ["#A8D8EA", "#FFB7B2", "#FFDAC1", "#B5EAD7", "#C7CEEA"][i]
            task.startTime = calendar.date(bySettingHour: 8 + i, minute: 0, second: 0, of: now)
            task.durationMinutes = [15, 30, 90, 45, 30][i]
            task.isCompleted = i < 2
            task.completedAt = i < 2 ? now : nil
            task.createdAt = now
        }

        let settings = UserSettings(context: context)
        settings.id = UUID()
        settings.wakeTime = calendar.date(bySettingHour: 7, minute: 30, second: 0, of: now)
        settings.onboardingCompleted = true
        settings.preferredLocale = "en"

        do {
            try context.save()
        } catch {
            fatalError("Preview CoreData save failed: \(error)")
        }
        return controller
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Tempa")

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        } else {
            guard let description = container.persistentStoreDescriptions.first else {
                fatalError("No persistent store description found")
            }
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.Bohdan-Rybak.Tempa---Visual-Planner"
            )
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("CoreData store failed to load: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    #if DEBUG
    /// Dev-only "factory reset": deletes every record object-by-object (NOT a
    /// batch delete — CloudKit only syncs tombstones for context deletions), so
    /// the wipe propagates to iCloud instead of being resurrected by it.
    static func wipeAllData() {
        let ctx = shared.container.viewContext
        for entity in ["TaskBlock", "UserSettings", "CompletionStreak"] {
            let req = NSFetchRequest<NSManagedObject>(entityName: entity)
            for object in (try? ctx.fetch(req)) ?? [] { ctx.delete(object) }
        }
        try? ctx.save()
        let d = UserDefaults.standard
        ["nudgesEnabled", "trialReminderWanted", "appLanguage",
         "tempa_last_app_open", "tempa_welcome_back_last_shown",
         "focus_session_snapshot", "todayGrouping", "todaySorting"].forEach { d.removeObject(forKey: $0) }
        print("[Tempa] DEBUG wipe: all local data deleted, tombstones will sync to CloudKit")
    }
    #endif
}
