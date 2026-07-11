import UserNotifications

/// A single, warm "come back to focus" nudge — fired ~3 minutes after the user
/// leaves the app while a focus session is running. Never nags: one gentle tap on
/// the shoulder, then silence. Returning to the app (or finishing) cancels it.
/// Respects the same "Gentle nudges" toggle as task reminders.
enum FocusNudge {
    private static let id = "focus-nudge"
    /// 3 minutes away → one nudge. Also the grace window for the session itself:
    /// absences up to this long still count as focus; longer ones become pause time.
    static let delay: TimeInterval = 3 * 60

    /// Warm, shame-free copy. Picked at random so it stays human, never robotic.
    /// Tone rule: supportive friend, zero guilt, zero "what are you doing" energy.
    private static let lines: [(title: String, body: String)] = [
        ("Your tempo's still going",
         "No rush, no guilt — your focus is holding your spot for whenever you're ready."),
        ("Still here for you",
         "Got pulled away? Happens to all of us. Come back whenever — your timer kept your place."),
        ("Whenever you're ready",
         "Your focus is paused on the world, not on you. Drop back in, no pressure."),
        ("One breath, then back?",
         "You stepped away, and that's okay. Your tempo's still flowing when you want it."),
        ("Your focus saved you a seat",
         "No nagging here, just a gentle wave. Your session's quietly waiting."),
        ("Easy does it",
         "Lost the thread for a sec? Totally normal. Your focus is right where you left it."),
    ]

    /// Schedule the one-shot nudge. Call when the app backgrounds mid-session.
    static func schedule() {
        guard TaskNotifications.nudgesEnabled else { return }
        guard let pick = lines.randomElement() else { return }

        let content = UNMutableNotificationContent()
        content.title = pick.title
        content.body = pick.body
        content.sound = .default
        content.interruptionLevel = .active

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Cancel any pending or already-shown nudge. Call when the app returns to the
    /// foreground or the session ends.
    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
}
