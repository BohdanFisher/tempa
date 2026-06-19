import Foundation

final class BreakdownRateLimiter {
    private let maxFreePerDay = 3
    private let countKey = "tempa_breakdown_count"
    private let dateKey = "tempa_breakdown_date"

    var usedToday: Int {
        resetIfNewDay()
        return UserDefaults.standard.integer(forKey: countKey)
    }

    var remaining: Int {
        max(0, maxFreePerDay - usedToday)
    }

    func canUse(isPro: Bool) -> Bool {
        if isPro { return true }
        resetIfNewDay()
        return usedToday < maxFreePerDay
    }

    func recordUse() {
        resetIfNewDay()
        UserDefaults.standard.set(usedToday + 1, forKey: countKey)
    }

    private func resetIfNewDay() {
        let today = Calendar.current.startOfDay(for: Date())
        let lastDate = UserDefaults.standard.object(forKey: dateKey) as? Date ?? .distantPast
        let lastDay = Calendar.current.startOfDay(for: lastDate)

        if today > lastDay {
            UserDefaults.standard.set(0, forKey: countKey)
            UserDefaults.standard.set(today, forKey: dateKey)
        }
    }
}
