import SwiftUI
import SwiftData

@main
struct CalmilesApp: App {
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var subscriptions = SubscriptionManager.shared
    @StateObject private var tripDetection = TripDetectionService.shared

    private let container = CalmilesModelContainer.make()

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
