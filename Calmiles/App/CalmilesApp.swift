import SwiftUI
import SwiftData

@main
struct CalmilesApp: App {
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var subscriptions = SubscriptionManager.shared
    @StateObject private var tripDetection = TripDetectionService.shared
    @StateObject private var friendShare = FriendSharePromptStore.shared

    @State private var showSplash: Bool = Self.shouldShowSplashOnLaunch
    @State private var showSharePrompt = false
    @State private var showShareSheet = false

    private let container = CalmilesModelContainer.make()

    /// Cold-start branded splash; skipped for UI tests.
    private static var shouldShowSplashOnLaunch: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-UITesting")
            || args.contains("-UITestSkipOnboarding")
            || args.contains("-UITestReset") {
            return false
        }
        #endif
        return true
    }

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
            ZStack {
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
                .environmentObject(friendShare)
                .modelContainer(container)
                .preferredColorScheme(nil)
                .task {
                    await subscriptions.refreshEntitlements()
                    wireTripDetection()
                    if settings.settings.hasCompletedOnboarding, settings.settings.autoDetectEnabled {
                        tripDetection.start()
                    }
                    if settings.settings.hasCompletedOnboarding {
                        friendShare.recordMeaningfulOpenIfNeeded()
                        // Soft prompt after splash finishes (or immediately if splash skipped)
                        scheduleSharePromptIfNeeded(delay: showSplash ? 2.0 : 0.8)
                    }
                }

                if showSplash {
                    BotlandStudioSplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeOut(duration: 0.35), value: showSplash)
            .task(id: showSplash) {
                guard showSplash else { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000) // ~1.5s branded launch
                withAnimation(.easeOut(duration: 0.35)) {
                    showSplash = false
                }
            }
            .alert("Enjoying Calmiles?", isPresented: $showSharePrompt) {
                Button("Share with friends") {
                    friendShare.markShared()
                    showShareSheet = true
                }
                Button("Not now", role: .cancel) {
                    friendShare.markDismissed()
                }
            } message: {
                Text("If Calmiles is helping you track mileage, share it with a friend who freelances too.")
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityView(activityItems: [StudioURLs.friendShareText, StudioURLs.website])
            }
        }
    }

    private func scheduleSharePromptIfNeeded(delay: TimeInterval) {
        guard friendShare.shouldShowSoftPrompt else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if friendShare.shouldShowSoftPrompt, !showSplash {
                showSharePrompt = true
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
