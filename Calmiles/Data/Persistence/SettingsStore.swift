import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults: UserDefaults
    private let key = "calmiles.appSettings"

    @Published var settings: AppSettings {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-UITestReset") {
            defaults.removeObject(forKey: key)
            self.settings = .default
            self.settings.rolloverFreeTierIfNeeded()
            return
        }
        if args.contains("-UITestSkipOnboarding") {
            var s = AppSettings.default
            s.hasCompletedOnboarding = true
            s.country = .au
            s.distanceUnit = .kilometers
            s.selectedRatePresetID = RateTable.activePreset(for: .au)?.id
            s.autoDetectEnabled = false
            self.settings = s
            if let data = try? JSONEncoder().encode(s) {
                defaults.set(data, forKey: key)
            }
            return
        }
        #endif
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }
        self.settings.rolloverFreeTierIfNeeded()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
        WidgetSharedStore.writeSummary(from: settings)
    }

    func completeOnboarding(country: CountryCode) {
        settings.country = country
        settings.distanceUnit = country.defaultDistanceUnit
        settings.selectedRatePresetID = RateTable.activePreset(for: country)?.id
        settings.hasCompletedOnboarding = true
    }

    func recordAutoTripIfNeeded(isPro: Bool) -> Bool {
        settings.rolloverFreeTierIfNeeded()
        if isPro { return true }
        if settings.freeAutoTripsUsedThisMonth >= AppSettings.freeAutoTripLimit {
            return false
        }
        settings.freeAutoTripsUsedThisMonth += 1
        return true
    }

    func deleteAllLocalSettings() {
        settings = .default
        defaults.removeObject(forKey: key)
    }
}
