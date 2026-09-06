import Foundation
import CoreLocation
import os.log

/// Background trip auto-detect via Core Location significant-change + visit monitoring.
/// Honest battery disclosure is in Info.plist and onboarding.
@MainActor
final class TripDetectionService: NSObject, ObservableObject {
    static let shared = TripDetectionService()

    private let logger = Logger(subsystem: "studio.botland.calmiles", category: "TripDetection")
    private let locationManager = CLLocationManager()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isTracking = false
    @Published private(set) var activePoints: [CoordinatePoint] = []
    @Published var lastErrorMessage: String?

    /// Callback when a trip is finalized (start/end/points/distance).
    var onTripCompleted: ((Date, Date, [CoordinatePoint], Double) -> Void)?

    private var tripStart: Date?
    private var isInMotionTrip = false
    private let minTripMeters: Double = 300
    private let stationaryTimeout: TimeInterval = 300
    private var lastMovementAt: Date?

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50
        locationManager.activityType = .automotiveNavigation
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
    }

    func requestWhenInUse() {
        locationManager.requestWhenInUseAuthorization()
    }

    func requestAlways() {
        locationManager.requestAlwaysAuthorization()
    }

    func start() {
        authorizationStatus = locationManager.authorizationStatus
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            lastErrorMessage = "Location permission is required for auto-detect."
            return
        }
        locationManager.startUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            logger.info("Significant location changes started")
        }
        isTracking = true
        logger.info("Trip detection started")
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        finalizeTripIfNeeded()
        isTracking = false
        logger.info("Trip detection stopped")
    }

    // MARK: - DEBUG sample injector (Simulator)

    #if DEBUG
    func injectSampleTrip() {
        let now = Date()
        let start = now.addingTimeInterval(-2_400)
        // Rough SF → nearby path (~8 miles)
        let points: [CoordinatePoint] = [
            .init(latitude: 37.7749, longitude: -122.4194, timestamp: start),
            .init(latitude: 37.7849, longitude: -122.4094, timestamp: start.addingTimeInterval(600)),
            .init(latitude: 37.8049, longitude: -122.3994, timestamp: start.addingTimeInterval(1200)),
            .init(latitude: 37.8199, longitude: -122.4783, timestamp: start.addingTimeInterval(1800)),
            .init(latitude: 37.8199, longitude: -122.4783, timestamp: now),
        ]
        let meters = DistanceCalculator.pathLengthMeters(points)
        onTripCompleted?(start, now, points, meters)
        logger.debug("Injected sample trip \(meters, privacy: .public) m")
    }
    #endif

    private func handleLocation(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 100 else { return }
        let point = CoordinatePoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp,
            speed: location.speed >= 0 ? location.speed : nil,
            horizontalAccuracy: location.horizontalAccuracy
        )

        let speed = location.speed
        let moving = speed > 4.0 // m/s ~ 9 mph

        if moving {
            if !isInMotionTrip {
                isInMotionTrip = true
                tripStart = location.timestamp
                activePoints = [point]
            } else {
                activePoints.append(point)
            }
            lastMovementAt = location.timestamp
        } else if isInMotionTrip {
            activePoints.append(point)
            if let last = lastMovementAt, location.timestamp.timeIntervalSince(last) > stationaryTimeout {
                finalizeTripIfNeeded()
            }
        }
    }

    private func finalizeTripIfNeeded() {
        guard isInMotionTrip, let start = tripStart, !activePoints.isEmpty else {
            resetTripState()
            return
        }
        let end = activePoints.last?.timestamp ?? Date()
        let meters = DistanceCalculator.pathLengthMeters(activePoints)
        if meters >= minTripMeters {
            onTripCompleted?(start, end, activePoints, meters)
        }
        resetTripState()
    }

    private func resetTripState() {
        isInMotionTrip = false
        tripStart = nil
        activePoints = []
        lastMovementAt = nil
    }
}

extension TripDetectionService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            AnalyticsStub.log("location_auth", ["status": "\(manager.authorizationStatus.rawValue)"])
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            locations.forEach { self.handleLocation($0) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastErrorMessage = error.localizedDescription
            self.logger.error("Location error: \(error.localizedDescription, privacy: .public)")
            CrashProtocolStub.record(error)
        }
    }
}
