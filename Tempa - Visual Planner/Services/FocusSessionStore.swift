import Foundation

/// A snapshot of the running focus session, nailed down in UserDefaults so the
/// session survives the app being killed (task switcher, memory pressure, reboot).
/// The Focus screen restores it on appear.
struct FocusSessionSnapshot: Codable {
    var sessionStart: Date
    var selectedMinutes: Int
    var pauseAccum: TimeInterval
    var isPaused: Bool
    var pauseStart: Date?
    var category: String?
    /// When the user left the app; nil while in the foreground. Used to decide
    /// whether the absence stays counted (short hop) or becomes pause time.
    var backgroundedAt: Date?
}

enum FocusSessionStore {
    private static let key = "focus_session_snapshot"

    static func save(_ snap: FocusSessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snap) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> FocusSessionSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FocusSessionSnapshot.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
