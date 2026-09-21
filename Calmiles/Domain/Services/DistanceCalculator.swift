import Foundation
import CoreLocation

enum DistanceCalculator {
    /// Earth radius in meters (WGS-84 mean).
    private static let earthRadiusMeters: Double = 6_371_000

    /// Haversine distance in meters between two coordinates.
    static func haversineMeters(from a: CoordinatePoint, to b: CoordinatePoint) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(h), sqrt(max(0, 1 - h)))
        return earthRadiusMeters * c
    }

    static func pathLengthMeters(_ points: [CoordinatePoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 1..<points.count {
            let segment = haversineMeters(from: points[i - 1], to: points[i])
            // Ignore absurd GPS jumps (> 2 km between consecutive samples without time context)
            if segment < 2_000 {
                total += segment
            } else if let t0 = Optional(points[i - 1].timestamp), let t1 = Optional(points[i].timestamp) {
                let dt = t1.timeIntervalSince(t0)
                // Allow longer jumps if time elapsed implies reasonable speed (< 50 m/s ~ 180 km/h)
                if dt > 0, segment / dt < 50 {
                    total += segment
                }
            }
        }
        return total
    }

    static func metersToMiles(_ meters: Double) -> Double { meters / 1609.344 }
    static func metersToKilometers(_ meters: Double) -> Double { meters / 1000.0 }
    static func milesToMeters(_ miles: Double) -> Double { miles * 1609.344 }
    static func kilometersToMeters(_ km: Double) -> Double { km * 1000.0 }

    static func convert(meters: Double, to unit: DistanceUnit) -> Double {
        switch unit {
        case .miles: return metersToMiles(meters)
        case .kilometers: return metersToKilometers(meters)
        }
    }

    static func convert(value: Double, from: DistanceUnit, to: DistanceUnit) -> Double {
        guard from != to else { return value }
        let meters = from == .miles ? milesToMeters(value) : kilometersToMeters(value)
        return convert(meters: meters, to: to)
    }
}
