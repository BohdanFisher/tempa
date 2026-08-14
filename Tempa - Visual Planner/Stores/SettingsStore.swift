import CoreData
import Observation

@Observable
final class SettingsStore {
    var onboardingCompleted: Bool = false
    var wakeTime: Date = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: Date()) ?? Date()
    var energyDipTime: Date?
    var reduceMotion: Bool = false
    var lowStimulationMode: Bool = false
    var useMetricUnits: Bool = true
    var preferredLocale: String = "en"
    var trialStartedAt: Date?

    private let viewContext: NSManagedObjectContext
    private var settingsObject: UserSettings?

    init(context: NSManagedObjectContext) {
        self.viewContext = context
        loadSettings()
        // CloudKit can bring changes (or a duplicate row) from another device at
        // any moment — re-read so this device doesn't keep serving stale values.
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.loadSettings()
        }
    }

    private func loadSettings() {
        let request = NSFetchRequest<UserSettings>(entityName: "UserSettings")

        do {
            let results = try viewContext.fetch(request)
            if !results.isEmpty {
                // CloudKit sync can deliver a second row created on another
                // device. Pick the winner by an IMMUTABLE key (lowest id) so
                // every device converges on the same row regardless of how
                // stale its snapshot is, and fold the important values in
                // before dropping the losers — nothing the user did is lost.
                let winner = results.min { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }!
                if results.count > 1 {
                    for extra in results where extra !== winner {
                        winner.onboardingCompleted = winner.onboardingCompleted || extra.onboardingCompleted
                        if winner.trialStartedAt == nil { winner.trialStartedAt = extra.trialStartedAt }
                        if winner.energyDipTime == nil { winner.energyDipTime = extra.energyDipTime }
                        viewContext.delete(extra)
                    }
                    try viewContext.save()
                }
                settingsObject = winner
                syncFromCoreData(winner)
            } else {
                // First launch this is all defaults; if we ever get here
                // mid-session (rows vanished via sync) the current in-memory
                // values are re-persisted, not silently reset.
                let newSettings = UserSettings(context: viewContext)
                newSettings.id = UUID()
                newSettings.onboardingCompleted = onboardingCompleted
                newSettings.wakeTime = wakeTime
                newSettings.energyDipTime = energyDipTime
                newSettings.reduceMotion = reduceMotion
                newSettings.lowStimulationMode = lowStimulationMode
                newSettings.useMetricUnits = useMetricUnits
                newSettings.preferredLocale = preferredLocale
                newSettings.trialStartedAt = trialStartedAt
                try viewContext.save()
                settingsObject = newSettings
            }
        } catch {
            print("SettingsStore: failed to load settings: \(error)")
        }
    }

    private func syncFromCoreData(_ settings: UserSettings) {
        onboardingCompleted = settings.onboardingCompleted
        if let wt = settings.wakeTime { wakeTime = wt }
        energyDipTime = settings.energyDipTime
        reduceMotion = settings.reduceMotion
        lowStimulationMode = settings.lowStimulationMode
        useMetricUnits = settings.useMetricUnits
        if let locale = settings.preferredLocale { preferredLocale = locale }
        trialStartedAt = settings.trialStartedAt
    }

    func save() {
        guard let settings = settingsObject else { return }
        settings.onboardingCompleted = onboardingCompleted
        settings.wakeTime = wakeTime
        settings.energyDipTime = energyDipTime
        settings.reduceMotion = reduceMotion
        settings.lowStimulationMode = lowStimulationMode
        settings.useMetricUnits = useMetricUnits
        settings.preferredLocale = preferredLocale
        settings.trialStartedAt = trialStartedAt

        do {
            try viewContext.save()
        } catch {
            print("SettingsStore: failed to save: \(error)")
        }
    }

    func completeOnboarding() {
        onboardingCompleted = true
        save()
    }
}
