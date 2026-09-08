import Foundation
import CoreLocation

/// Pure rules for when a drive starts and whether a late wake-up should
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
    static let maxBackfillAge: TimeInterval = 40 * 60
    /// Don't treat a GPS jump as a departure.
    static let maxImpliedSpeed: Double = 42 // m/s ~ 150 km/h
    /// Movement from the last park that counts as leaving, even if speed is invalid.
    static let departureDistanceMeters: Double = 160
    /// Speed that counts as driving when the device reports it.
    static let movingSpeedThreshold: Double = 2.2 // m/s ~ 8 km/h
    static let minTripMeters: Double = 300

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
        accuracy >= 0 && accuracy <= 1_500
    }

    /// Prefer tighter fixes for the recorded path; still accept moderate error mid-drive.
    static func isUsablePathPoint(accuracy: Double) -> Bool {
        accuracy >= 0 && accuracy <= 200
    }

    static func isMoving(speed: Double) -> Bool {
        speed >= movingSpeedThreshold
    }

    /// Left the last parked point: valid driving speed, or far enough that a missed
    /// speed reading still counts (GPS speed is often -1 on the first wake).
    static func hasDeparted(anchor: Anchor?, latitude: Double, longitude: Double, speed: Double, timestamp: Date) -> Bool {
        if isMoving(speed: speed) { return true }
        guard let anchor else { return false }
        let distance = meters(from: anchor, to: latitude, longitude: longitude)
        guard distance >= departureDistanceMeters else { return false }
        let dt = timestamp.timeIntervalSince(anchor.timestamp)
        if dt <= 1 { return distance >= departureDistanceMeters }
        let implied = distance / dt
        return implied <= maxImpliedSpeed
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
        guard distance >= 40 else { return nil }
        if age < 1 { return start }
        let implied = distance / age
        guard implied <= maxImpliedSpeed else { return nil }
        return start
    }
}
