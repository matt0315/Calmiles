import Foundation
import CoreLocation

enum GeocodingService {
    enum GeocodeError: Error {
        case emptyAddress
        case notFound
    }

    /// Forward-geocode a free-form address string.
    static func coordinate(for address: String) async throws -> CLLocationCoordinate2D {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GeocodeError.emptyAddress }
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.geocodeAddressString(trimmed)
        guard let loc = placemarks.first?.location else { throw GeocodeError.notFound }
        return loc.coordinate
    }

    /// Build a two-point start→finish route for MapKit (straight line between geocoded addresses).
    /// Returns nil if either address cannot be geocoded.
    static func routeEndpoints(
        from fromAddress: String,
        to toAddress: String,
        startDate: Date,
        endDate: Date
    ) async -> [CoordinatePoint]? {
        do {
            async let startCoord = coordinate(for: fromAddress)
            async let endCoord = coordinate(for: toAddress)
            let start = try await startCoord
            let end = try await endCoord
            return [
                CoordinatePoint(latitude: start.latitude, longitude: start.longitude, timestamp: startDate),
                CoordinatePoint(latitude: end.latitude, longitude: end.longitude, timestamp: endDate),
            ]
        } catch {
            return nil
        }
    }
}
