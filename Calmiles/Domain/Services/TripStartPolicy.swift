import Foundation
import CoreLocation

/// Pure rules for when a drive starts/ends and whether a late wake-up should
/// prepend the last stationary point. Kept separate so the detector can be tested
/// without Core Location hardware.
enum TripStartPolicy {
    /// Recent parked/stationary fix that can seed a trip start.
    struct Anchor: Equatable, Sendable {
        var latitude: Double
        var longitude: Double
        var timestamp: Date
        var horizontalAccuracy: Double
    }

    /// Ignore significant-change wakes older than this when backfilling.
    static let maxBackfillAge: TimeInterval = 60 * 60
    /// Don't treat a GPS jump as a departure.
    static let maxImpliedSpeed: Double = 42 // m/s ~ 150 km/h
    /// Movement from the last park that counts as leaving, even if speed is invalid.
    /// Prefer capturing early over waiting for a long GPS gap.
    static let departureDistanceMeters: Double = 55
    /// Speed that counts as driving when the device reports it.
    static let movingSpeedThreshold: Double = 1.5 // m/s ~ 5.4 km/h
    /// While recording, treat this as still moving (keeps dwell timer from firing).
    static let keepAliveSpeedThreshold: Double = 1.0 // m/s ~ 3.6 km/h
    /// Cluster radius used to decide "parked at destination".
    static let dwellRadiusMeters: Double = 90
    /// How long the device must stay in the dwell cluster before ending a trip.
    static let dwellTimeout: TimeInterval = 150
    static let minTripMeters: Double = 120
    /// Cached / deferred samples older than this are not used to start a trip.
    static let maxSampleAge: TimeInterval = 180

    static func meters(from a: Anchor, to latitude: Double, longitude: Double) -> Double {
        DistanceCalculator.haversineMeters(
            from: CoordinatePoint(latitude: a.latitude, longitude: a.longitude, timestamp: a.timestamp),
            to: CoordinatePoint(latitude: latitude, longitude: longitude)
        )
    }

    static func meters(from a: CoordinatePoint, to b: CoordinatePoint) -> Double {
        DistanceCalculator.haversineMeters(from: a, to: b)
    }

    /// A location is usable for departure detection even when coarse (significant-change).
    static func isUsableWake(accuracy: Double) -> Bool {
        accuracy >= 0 && accuracy <= 1_800
    }

    /// Prefer tighter fixes for the recorded path; still accept moderate error mid-drive.
    static func isUsablePathPoint(accuracy: Double) -> Bool {
        accuracy >= 0 && accuracy <= 250
    }

    static func isMoving(speed: Double) -> Bool {
        speed >= movingSpeedThreshold
    }

    /// Drop ancient cached fixes so a stale sample cannot look like an instant jump.
    static func isFreshSample(timestamp: Date, now: Date = Date(), maxAge: TimeInterval = maxSampleAge) -> Bool {
        let age = now.timeIntervalSince(timestamp)
        return age >= -5 && age <= maxAge
    }

    /// Left the last parked point: valid driving speed, or far enough that a missed
    /// speed reading still counts (GPS speed is often -1 on the first wake).
    static func hasDeparted(
        anchor: Anchor?,
        latitude: Double,
        longitude: Double,
        speed: Double,
        timestamp: Date,
        motionIndicatesDrive: Bool = false
    ) -> Bool {
        if motionIndicatesDrive { return true }
        if isMoving(speed: speed) { return true }
        guard let anchor else { return false }
        let dt = timestamp.timeIntervalSince(anchor.timestamp)
        // Stale cached sample from before we parked is not a departure.
        if dt < -2 { return false }
        let distance = meters(from: anchor, to: latitude, longitude: longitude)
        guard distance >= departureDistanceMeters else { return false }
        if dt <= 1 { return true }
        let implied = distance / dt
        return implied <= maxImpliedSpeed
    }

    /// True when the latest samples show the user is still progressing along a drive.
    static func isActivelyMoving(speed: Double, from previous: CoordinatePoint?, to current: CoordinatePoint) -> Bool {
        if speed >= keepAliveSpeedThreshold { return true }
        guard let previous else { return false }
        let dt = current.timestamp.timeIntervalSince(previous.timestamp)
        guard dt > 0 else { return false }
        let distance = meters(from: previous, to: current)
        // ~1 m/s average between samples keeps a trip alive through brief GPS gaps.
        if distance / dt >= 0.8 && distance >= 20 { return true }
        return false
    }

    /// Parked long enough near the latest cluster to end a trip (destination dwell).
    /// Uses recent path points only — not distance from the original departure —
    /// so trips end at work/errands instead of only when returning near home.
    static func isStationaryDwell(
        points: [CoordinatePoint],
        now: Date = Date(),
        timeout: TimeInterval = dwellTimeout,
        radius: Double = dwellRadiusMeters
    ) -> Bool {
        guard let latest = points.last else { return false }
        let windowStart = now.addingTimeInterval(-timeout)
        // Need evidence that covers most of the dwell window.
        guard latest.timestamp >= windowStart.addingTimeInterval(-30) else { return false }
        let inWindow = points.filter { $0.timestamp >= windowStart }
        guard let earliest = inWindow.first else { return false }
        guard now.timeIntervalSince(earliest.timestamp) >= timeout * 0.85 else { return false }

        for point in inWindow {
            if let speed = point.speed, speed >= keepAliveSpeedThreshold { return false }
            if meters(from: point, to: latest) > radius { return false }
        }
        return true
    }

    /// End when clustered dwell is satisfied, or when nothing has moved for the dwell window.
    /// Sparse significant-change samples often never fill a 3-minute cluster, so a
    /// last-movement timeout is required to actually finish trips after parking.
    static func shouldFinalizeTrip(
        points: [CoordinatePoint],
        lastMovementAt: Date?,
        now: Date = Date(),
        timeout: TimeInterval = dwellTimeout
    ) -> Bool {
        if isStationaryDwell(points: points, now: now, timeout: timeout) { return true }
        if let lastMovementAt, now.timeIntervalSince(lastMovementAt) >= timeout {
            return true
        }
        return false
    }

    /// If detection woke up after the car had already left, prepend the last park
    /// when it is recent and the implied speed is a plausible drive.
    static func backfillStart(anchor: Anchor?, firstMoving: CoordinatePoint) -> CoordinatePoint? {
        guard let anchor else { return nil }
        let age = firstMoving.timestamp.timeIntervalSince(anchor.timestamp)
        guard age >= 0, age <= maxBackfillAge else { return nil }

        let start = CoordinatePoint(
            latitude: anchor.latitude,
            longitude: anchor.longitude,
            timestamp: anchor.timestamp,
            horizontalAccuracy: anchor.horizontalAccuracy
        )
        let distance = meters(from: start, to: firstMoving)
        // Already essentially the same place.
        guard distance >= 25 else { return nil }
        if age < 1 { return start }
        let implied = distance / age
        guard implied <= maxImpliedSpeed else { return nil }
        return start
    }
}
