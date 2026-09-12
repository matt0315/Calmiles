import Foundation
import CoreLocation
import os.log

/// Background trip auto-detect via Core Location visits, significant-change, and
/// standard updates. Starts from the last parked point when a wake-up is late,
/// ends on destination dwell (not “back near home”), and persists an in-flight
/// trip across process death. Honest battery disclosure is in Info.plist / onboarding.
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
    private var lastMovementAt: Date?
    private var stationaryAnchor: TripStartPolicy.Anchor?
    /// Recent fixes while still parked, so a late "moving" sample can include the departure.
    private var recentFixes: [CoordinatePoint] = []
    private let recentFixLimit = 16

    private enum StoreKeys {
        static let lat = "calmiles.detect.lastLat"
        static let lon = "calmiles.detect.lastLon"
        static let ts = "calmiles.detect.lastTs"
        static let acc = "calmiles.detect.lastAcc"
        static let activeTrip = "calmiles.detect.activeTrip.v1"
    }

    private struct ActiveTripSnapshot: Codable {
        var start: Date
        var points: [CoordinatePoint]
        var lastMovementAt: Date?
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
        restoreActiveTripIfNeeded()
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
        configureBackgroundUpdatesIfAllowed()
        applyIdleOrTripAccuracy()
        locationManager.startUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
        locationManager.startMonitoringVisits()
        // Nudge a fresh fix after wake so late departures aren't waiting on the filter alone.
        locationManager.requestLocation()
        isTracking = true
        logger.info("Trip detection started (auth=\(self.authorizationStatus.rawValue, privacy: .public), inflight=\(self.isInMotionTrip, privacy: .public))")
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopMonitoringVisits()
        finalizeTripIfNeeded(reason: "stop")
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

    private func configureBackgroundUpdatesIfAllowed() {
        if authorizationStatus == .authorizedAlways {
            locationManager.allowsBackgroundLocationUpdates = true
        }
    }

    private func applyIdleAccuracy() {
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 40
    }

    private func applyTripAccuracy() {
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 15
    }

    private func applyIdleOrTripAccuracy() {
        if isInMotionTrip { applyTripAccuracy() } else { applyIdleAccuracy() }
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

        if !isInMotionTrip {
            if departed {
                beginOrContinueTrip(with: point)
                lastMovementAt = location.timestamp
                persistActiveTrip()
            } else {
                // Still parked (or creeping). Keep the last good place so a late wake can backfill.
                if TripStartPolicy.isUsablePathPoint(accuracy: accuracy) || stationaryAnchor == nil {
                    rememberStationary(point)
                }
                appendRecent(point)
            }
            return
        }

        // In-trip: keep recording; end on destination dwell (not “near original park”).
        let previous = activePoints.last
        appendInTrip(point)
        if TripStartPolicy.isActivelyMoving(speed: speed, from: previous, to: point) {
            lastMovementAt = location.timestamp
        }
        persistActiveTrip()

        if TripStartPolicy.isStationaryDwell(points: activePoints, now: location.timestamp) {
            rememberStationary(point)
            finalizeTripIfNeeded(reason: "dwell")
        }
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
        } else {
            appendInTrip(point)
        }
    }

    private func appendInTrip(_ point: CoordinatePoint) {
        if TripStartPolicy.isUsablePathPoint(accuracy: point.horizontalAccuracy ?? 0)
            || point.horizontalAccuracy == nil {
            activePoints.append(point)
        } else if let last = activePoints.last {
            let gap = TripStartPolicy.meters(from: last, to: point)
            // Keep coarse significant-change fixes so background wakes don't drop the path.
            if gap > 60 {
                activePoints.append(point)
            }
        } else {
            activePoints.append(point)
        }
        // Cap memory for very long drives; keep ends for backfill/finalize.
        if activePoints.count > 2_500 {
            let head = Array(activePoints.prefix(1))
            let tail = Array(activePoints.suffix(2_000))
            activePoints = head + tail
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
                persistActiveTrip()
                logger.info("Trip started from visit departure")
                // Ask for a fresh stream so the drive is followed even if the next SLC is slow.
                locationManager.requestLocation()
            } else if let first = activePoints.first, when < first.timestamp {
                activePoints.insert(point, at: 0)
                tripStart = when
                persistActiveTrip()
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
                finalizeTripIfNeeded(reason: "visit_arrival")
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
        if let last = recentFixes.last, TripStartPolicy.meters(from: last, to: point) < 12 { return }
        recentFixes.append(point)
        if recentFixes.count > recentFixLimit {
            recentFixes.removeFirst(recentFixes.count - recentFixLimit)
        }
    }

    private func finalizeTripIfNeeded(reason: String) {
        guard isInMotionTrip, let start = tripStart ?? activePoints.first?.timestamp, !activePoints.isEmpty else {
            clearActiveTripStore()
            resetTripState()
            return
        }
        let end = activePoints.last?.timestamp ?? Date()
        let meters = DistanceCalculator.pathLengthMeters(activePoints)
        if meters >= TripStartPolicy.minTripMeters {
            onTripCompleted?(start, end, activePoints, meters)
            logger.info("Trip finalized \(meters, privacy: .public) m reason=\(reason, privacy: .public)")
        } else {
            logger.info("Discarded short movement \(meters, privacy: .public) m reason=\(reason, privacy: .public)")
        }
        if let last = activePoints.last {
            rememberStationary(last)
        }
        clearActiveTripStore()
        resetTripState()
        applyIdleAccuracy()
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

    private func persistActiveTrip() {
        guard isInMotionTrip, let start = tripStart ?? activePoints.first?.timestamp, !activePoints.isEmpty else {
            clearActiveTripStore()
            return
        }
        let snap = ActiveTripSnapshot(start: start, points: activePoints, lastMovementAt: lastMovementAt)
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: StoreKeys.activeTrip)
        }
    }

    private func clearActiveTripStore() {
        UserDefaults.standard.removeObject(forKey: StoreKeys.activeTrip)
    }

    private func restoreActiveTripIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: StoreKeys.activeTrip),
              let snap = try? JSONDecoder().decode(ActiveTripSnapshot.self, from: data),
              !snap.points.isEmpty else { return }
        // Drop ancient in-flight snapshots (e.g. leftover after a crash days ago).
        let age = Date().timeIntervalSince(snap.points.last?.timestamp ?? snap.start)
        guard age <= 6 * 60 * 60 else {
            clearActiveTripStore()
            return
        }
        isInMotionTrip = true
        tripStart = snap.start
        activePoints = snap.points
        lastMovementAt = snap.lastMovementAt
        if let last = snap.points.last {
            lastKnownCoordinate = CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)
        }
        logger.info("Restored in-flight trip with \(snap.points.count, privacy: .public) points")
    }
}

extension TripDetectionService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedAlways {
                manager.allowsBackgroundLocationUpdates = true
                if self.isTracking {
                    manager.startUpdatingLocation()
                    manager.startMonitoringSignificantLocationChanges()
                    manager.startMonitoringVisits()
                }
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
            // requestLocation() occasionally fails with temporary denials; don't spam UI.
            if let cl = error as? CLError, cl.code == .locationUnknown { return }
            self.lastErrorMessage = error.localizedDescription
            self.logger.error("Location error: \(error.localizedDescription, privacy: .public)")
            CrashProtocolStub.record(error)
        }
    }
}
