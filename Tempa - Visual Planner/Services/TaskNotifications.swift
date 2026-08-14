import Foundation
import UserNotifications
import CoreData

/// Schedules a local notification 10 minutes before each upcoming task starts.
/// Rather than hooking every mutation, we re-sync all reminders whenever the
/// Core Data context saves (and at launch) — simple and always consistent.
enum TaskNotifications {
    private static let prefix = "task-10min-"
    private static let leadMinutes: TimeInterval = 10 * 60

    /// "Gentle nudges" toggle in Settings — default on.
    static var nudgesEnabled: Bool {
        UserDefaults.standard.object(forKey: "nudgesEnabled") as? Bool ?? true
    }

    /// CloudKit imports land as bursts of transactions — collapse them into
    /// one resync instead of one per transaction.
    private static var pendingResync: DispatchWorkItem?
    private static func scheduleResync(context: NSManagedObjectContext) {
        pendingResync?.cancel()
        let work = DispatchWorkItem { rescheduleAll(context: context) }
        pendingResync = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// Begin observing saves so reminders stay in sync with the task list.
    static func startObserving(_ context: NSManagedObjectContext) {
        // Without a delegate iOS silently swallows notifications that fire while
        // the app is open — which reads as "reminders don't work at all".
        UNUserNotificationCenter.current().delegate = TaskNotificationDelegate.shared
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: context,
            queue: .main
        ) { _ in
            scheduleResync(context: context)
        }
        // Tasks synced in from another device never touch the local save path —
        // reschedule on CloudKit imports too, or iPad-created tasks stay silent.
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { _ in
            scheduleResync(context: context)
        }
        rescheduleAll(context: context)
    }

    /// Clear our reminders and reschedule one 10 min before every future, incomplete task.
    static func rescheduleAll(context: NSManagedObjectContext) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ours = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)

            // Nudges turned off → clear everything and schedule nothing.
            guard nudgesEnabled else { return }

            context.perform {
                let req = NSFetchRequest<TaskBlock>(entityName: "TaskBlock")
                req.predicate = NSPredicate(
                    format: "isCompleted == NO AND startTime != nil AND startTime > %@",
                    Date() as NSDate
                )
                let tasks = (try? context.fetch(req)) ?? []
                for task in tasks {
                    guard let id = task.id, let start = task.startTime else { continue }
                    let fire = start.addingTimeInterval(-leadMinutes)
                    guard fire > Date() else { continue }

                    let content = UNMutableNotificationContent()
                    content.title = task.title ?? String(localized: "Upcoming task", bundle: .appLanguage)
                    content.body = String(localized: "Starts in 10 minutes.", bundle: .appLanguage)
                    content.sound = .default

                    let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    let request = UNNotificationRequest(identifier: prefix + id.uuidString, content: content, trigger: trigger)
                    center.add(request)
                }
            }
        }
    }
}

/// Presents reminder banners even while the app is in the foreground.
final class TaskNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TaskNotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
