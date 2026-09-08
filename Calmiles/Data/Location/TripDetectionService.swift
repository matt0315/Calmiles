import Foundation
import CoreLocation
import os.log

/// Background trip auto-detect via Core Location visits, significant-change, and
/// standard updates. Starts from the last parked point when a wake-up is late.
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

    /// Last decent fix, used to bias manual address search toward where the user is.
    private(set) var lastKnownCoordinate: CLLocationCoordinate2D?

    /// Callback when a trip is finalized (start/end/points/distance).
    var onTripCompleted: ((Date, Date, [CoordinatePoint], Double) -> Void)?

    private var tripStart: Date?
    private var isInMotionTrip = false
    private let stationaryTimeout: TimeInterval = 240
    private var lastMovementAt: Date?
    private var stationaryAnchor: TripStartPolicy.Anchor?
    /// Recent fixes while still parked, so a late "moving" sample can include the departure.
    private var recentFixes: [CoordinatePoint] = []
    private let recentFixLimit = 12

    private enum StoreKeys {
        static let lat = "calmiles.detect.lastLat"
        static let lon = "calmiles.detect.lastLon"
        static let ts = "calmiles.detect.lastTs"
        static let acc = "calmiles.detect.lastAcc"
    }

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 40
        locationManager.activityType = .automotiveNavigation
        // Pausing drops the first half of a drive: iOS stays asleep until well after departure.
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
        loadPersistedAnchor()
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
        if authorizationStatus == .authorizedAlways {
            locationManager.allowsBackgroundLocationUpdates = true
        }
        applyIdleAccuracy()
        locationManager.startUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
        locationManager.startMonitoringVisits()
        isTracking = true
        logger.info("Trip detection started")
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopMonitoringVisits()
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

    private func applyIdleAccuracy() {
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50
    }

    private func applyTripAccuracy() {
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 20
    }

    private func handleLocation(_ location: CLLocation) {
        let accuracy = location.horizontalAccuracy
        guard TripStartPolicy.isUsableWake(accuracy: accuracy) else { return }

        let point = CoordinatePoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp,
            speed: location.speed >= 0 ? location.speed : nil,
            horizontalAccuracy: accuracy
        )
        lastKnownCoordinate = location.coordinate

        let speed = location.speed
        let departed = TripStartPolicy.hasDeparted(
            anchor: stationaryAnchor,
            latitude: point.latitude,
            longitude: point.longitude,
            speed: speed,
            timestamp: location.timestamp
        )

        if departed {
            beginOrContinueTrip(with: point)
            lastMovementAt = location.timestamp
            return
        }

        if isInMotionTrip {
            if TripStartPolicy.isUsablePathPoint(accuracy: accuracy) {
                activePoints.append(point)
            } else if let last = activePoints.last, TripStartPolicy.meters(from: last, to: point) > 120 {
                // Keep coarse significant-change fixes so the path isn't only the second half.
                activePoints.append(point)
            }
            if let last = lastMovementAt, location.timestamp.timeIntervalSince(last) > stationaryTimeout {
                rememberStationary(point)
                finalizeTripIfNeeded()
            }
            return
        }

        // Still parked (or creeping). Keep the last good place so a late wake can backfill.
        if TripStartPolicy.isUsablePathPoint(accuracy: accuracy) || stationaryAnchor == nil {
            rememberStationary(point)
        }
        appendRecent(point)
    }

    private func beginOrContinueTrip(with point: CoordinatePoint) {
        if !isInMotionTrip {
            isInMotionTrip = true
            applyTripAccuracy()
            var points: [CoordinatePoint] = []
            if let start = TripStartPolicy.backfillStart(anchor: stationaryAnchor, firstMoving: point) {
                points.append(start)
                tripStart = start.timestamp
            } else {
                tripStart = point.timestamp
            }
            // Include any recent pre-departure fixes that sit between the park and this wake.
            for prior in recentFixes where prior.timestamp < point.timestamp {
                if let first = points.first, prior.timestamp <= first.timestamp { continue }
                if points.contains(where: { abs($0.timestamp.timeIntervalSince(prior.timestamp)) < 1 }) { continue }
                points.append(prior)
            }
            points.append(point)
            points.sort { $0.timestamp < $1.timestamp }
            activePoints = points
            tripStart = points.first?.timestamp ?? point.timestamp
            recentFixes = []
            logger.info("Trip started, points \(points.count, privacy: .public)")
        } else if TripStartPolicy.isUsablePathPoint(accuracy: point.horizontalAccuracy ?? 0)
                    || point.horizontalAccuracy == nil {
            activePoints.append(point)
        } else if let last = activePoints.last {
            let gap = TripStartPolicy.meters(from: last, to: point)
            if gap > 80 {
                activePoints.append(point)
            }
        } else {
            activePoints.append(point)
        }
    }

    private func handleVisit(_ visit: CLVisit) {
        let accuracy = visit.horizontalAccuracy
        guard accuracy >= 0 else { return }
        let coordinate = visit.coordinate
        lastKnownCoordinate = coordinate

        let departed = visit.departureDate != .distantFuture
        let arrived = visit.arrivalDate != .distantFuture

        if departed {
            let when = visit.departureDate
            let anchor = TripStartPolicy.Anchor(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                timestamp: when,
                horizontalAccuracy: accuracy
            )
            // Visit departure is the parked origin, even if the next GPS fix is late.
            if stationaryAnchor == nil || when >= (stationaryAnchor?.timestamp ?? .distantPast) {
                stationaryAnchor = anchor
                persist(anchor)
            }
            let point = CoordinatePoint(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                timestamp: when,
                horizontalAccuracy: accuracy
            )
            if !isInMotionTrip {
                isInMotionTrip = true
                applyTripAccuracy()
                tripStart = when
                lastMovementAt = when
                activePoints = [point]
                recentFixes = []
                logger.info("Trip started from visit departure")
            } else if let first = activePoints.first, when < first.timestamp {
                activePoints.insert(point, at: 0)
                tripStart = when
            }
            return
        }

        if arrived {
            let point = CoordinatePoint(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                timestamp: visit.arrivalDate,
                horizontalAccuracy: accuracy
            )
            rememberStationary(point)
            if isInMotionTrip {
                activePoints.append(point)
                finalizeTripIfNeeded()
            }
        }
    }

    private func rememberStationary(_ point: CoordinatePoint) {
        let anchor = TripStartPolicy.Anchor(
            latitude: point.latitude,
            longitude: point.longitude,
            timestamp: point.timestamp,
            horizontalAccuracy: point.horizontalAccuracy ?? 100
        )
        stationaryAnchor = anchor
        persist(anchor)
        appendRecent(point)
    }

    private func appendRecent(_ point: CoordinatePoint) {
        if let last = recentFixes.last, TripStartPolicy.meters(from: last, to: point) < 15 { return }
        recentFixes.append(point)
        if recentFixes.count > recentFixLimit {
            recentFixes.removeFirst(recentFixes.count - recentFixLimit)
        }
    }

    private func finalizeTripIfNeeded() {
        guard isInMotionTrip, let start = tripStart ?? activePoints.first?.timestamp, !activePoints.isEmpty else {
            resetTripState()
            return
        }
        let end = activePoints.last?.timestamp ?? Date()
        let meters = DistanceCalculator.pathLengthMeters(activePoints)
        if meters >= TripStartPolicy.minTripMeters {
            onTripCompleted?(start, end, activePoints, meters)
            logger.info("Trip finalized \(meters, privacy: .public) m")
        } else {
            logger.info("Discarded short movement \(meters, privacy: .public) m")
        }
        if let last = activePoints.last {
            rememberStationary(point: last)
        }
        resetTripState()
        applyIdleAccuracy()
    }

    private func rememberStationary(point: CoordinatePoint) {
        rememberStationary(point)
    }

    private func resetTripState() {
        isInMotionTrip = false
        tripStart = nil
        activePoints = []
        lastMovementAt = nil
        recentFixes = []
    }

    private func persist(_ anchor: TripStartPolicy.Anchor) {
        let defaults = UserDefaults.standard
        defaults.set(anchor.latitude, forKey: StoreKeys.lat)
        defaults.set(anchor.longitude, forKey: StoreKeys.lon)
        defaults.set(anchor.timestamp.timeIntervalSince1970, forKey: StoreKeys.ts)
        defaults.set(anchor.horizontalAccuracy, forKey: StoreKeys.acc)
    }

    private func loadPersistedAnchor() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: StoreKeys.lat) != nil else { return }
        let lat = defaults.double(forKey: StoreKeys.lat)
        let lon = defaults.double(forKey: StoreKeys.lon)
        let ts = defaults.double(forKey: StoreKeys.ts)
        let acc = defaults.double(forKey: StoreKeys.acc)
        guard ts > 0 else { return }
        stationaryAnchor = TripStartPolicy.Anchor(
            latitude: lat,
            longitude: lon,
            timestamp: Date(timeIntervalSince1970: ts),
            horizontalAccuracy: acc > 0 ? acc : 100
        )
        lastKnownCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

extension TripDetectionService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedAlways {
                manager.allowsBackgroundLocationUpdates = true
            }
            AnalyticsStub.log("location_auth", ["status": "\(manager.authorizationStatus.rawValue)"])
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            locations.sorted { $0.timestamp < $1.timestamp }.forEach { self.handleLocation($0) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in
            self.handleVisit(visit)
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
