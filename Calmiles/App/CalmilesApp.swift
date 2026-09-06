import SwiftUI
import SwiftData

@main
struct CalmilesApp: App {
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var subscriptions = SubscriptionManager.shared
    @StateObject private var tripDetection = TripDetectionService.shared

    private let container = CalmilesModelContainer.make()

    init() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-UITestReset") || args.contains("-UITestSkipOnboarding") {
            // Ensure predictable UITest / screenshot state
            var s = AppSettings.default
            if args.contains("-UITestSkipOnboarding") {
                s.hasCompletedOnboarding = true
                s.country = .au
                s.distanceUnit = .kilometers
                s.selectedRatePresetID = RateTable.activePreset(for: .au)?.id
                s.autoDetectEnabled = false
            }
            if let data = try? JSONEncoder().encode(s) {
                UserDefaults.standard.set(data, forKey: "calmiles.appSettings")
            }
            // Reset shared singleton after writing defaults
            // SettingsStore.shared already may have loaded; force via Notification in DEBUG path below
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if settings.settings.hasCompletedOnboarding {
                    RootTabView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(settings)
            .environmentObject(subscriptions)
            .environmentObject(tripDetection)
            .modelContainer(container)
            .preferredColorScheme(nil)
            .task {
                await subscriptions.refreshEntitlements()
                wireTripDetection()
                if settings.settings.hasCompletedOnboarding, settings.settings.autoDetectEnabled {
                    tripDetection.start()
                }
            }
        }
    }

    private func wireTripDetection() {
        tripDetection.onTripCompleted = { [settings, subscriptions] start, end, points, meters in
            Task { @MainActor in
                let allowed = settings.recordAutoTripIfNeeded(isPro: subscriptions.isPro)
                guard allowed else {
                    AnalyticsStub.log("auto_trip_blocked_free_cap")
                    return
                }
                let trip = TripEntity(
                    startDate: start,
                    endDate: end,
                    distanceMeters: meters,
                    classification: .undecided,
                    purpose: "",
                    notes: "",
                    isManual: false,
                    isAutoDetected: true,
                    routePoints: points
                )
                do {
                    try TripRepository(context: container.mainContext).add(trip)
                    AnalyticsStub.log("auto_trip_saved")
                } catch {
                    CrashProtocolStub.record(error)
                }
            }
        }
    }
}
