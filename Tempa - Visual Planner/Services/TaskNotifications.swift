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

    /// Begin observing saves so reminders stay in sync with the task list.
    static func startObserving(_ context: NSManagedObjectContext) {
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: context,
            queue: .main
        ) { _ in
            rescheduleAll(context: context)
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
                    content.title = task.title ?? "Upcoming task"
                    content.body = "Starts in 10 minutes."
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
