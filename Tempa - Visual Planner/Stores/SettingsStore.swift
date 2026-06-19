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
    }

    private func loadSettings() {
        let request = NSFetchRequest<UserSettings>(entityName: "UserSettings")
        request.fetchLimit = 1

        do {
            let results = try viewContext.fetch(request)
            if let existing = results.first {
                settingsObject = existing
                syncFromCoreData(existing)
            } else {
                let newSettings = UserSettings(context: viewContext)
                newSettings.id = UUID()
                newSettings.wakeTime = wakeTime
                newSettings.preferredLocale = preferredLocale
                newSettings.useMetricUnits = useMetricUnits
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
