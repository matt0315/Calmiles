import Foundation
import CoreLocation
import MapKit

enum GeocodingService {
    enum GeocodeError: Error {
        case emptyAddress
        case notFound
        case routeUnavailable
    }

    /// Geocoded automobile directions between From and To.
    struct RoutedJourney: Sendable {
        var points: [CoordinatePoint]
        var distanceMeters: Double
        var expectedTravelTime: TimeInterval
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

    /// Geocode From/To and request MapKit automobile directions.
    /// Returns the route polyline (sampled coordinates), travelled distance, and ETA.
    static func directionsRoute(
        from fromAddress: String,
        to toAddress: String,
        startDate: Date
    ) async throws -> RoutedJourney {
        let fromTrimmed = fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let toTrimmed = toAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fromTrimmed.isEmpty, !toTrimmed.isEmpty else { throw GeocodeError.emptyAddress }

        async let startCoord = coordinate(for: fromTrimmed)
        async let endCoord = coordinate(for: toTrimmed)
        let start = try await startCoord
        let end = try await endCoord

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        let response: MKDirections.Response
        do {
            response = try await directions.calculate()
        } catch {
            throw GeocodeError.routeUnavailable
        }
        guard let route = response.routes.first else { throw GeocodeError.routeUnavailable }

        let coords = polylineCoordinates(route.polyline)
        guard coords.count >= 2 else { throw GeocodeError.routeUnavailable }

        let travel = max(route.expectedTravelTime, 60)
        let points = coords.enumerated().map { index, coord in
            let fraction = coords.count == 1 ? 0.0 : Double(index) / Double(coords.count - 1)
            let ts = startDate.addingTimeInterval(travel * fraction)
            return CoordinatePoint(latitude: coord.latitude, longitude: coord.longitude, timestamp: ts)
        }

        return RoutedJourney(
            points: points,
            distanceMeters: route.distance,
            expectedTravelTime: travel
        )
    }

    /// Convenience: nil on failure (for save paths that tolerate missing maps).
    static func directionsRouteOrNil(
        from fromAddress: String,
        to toAddress: String,
        startDate: Date
    ) async -> RoutedJourney? {
        do {
            return try await directionsRoute(from: fromAddress, to: toAddress, startDate: startDate)
        } catch {
            return nil
        }
    }

    private static func polylineCoordinates(_ polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        let count = polyline.pointCount
        guard count > 0 else { return [] }
        var coords = Array(repeating: kCLLocationCoordinate2DInvalid, count: count)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
        // Cap stored points so SwiftData blobs stay reasonable on long drives.
        let maxPoints = 200
        if coords.count <= maxPoints { return coords }
        let step = Double(coords.count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { i in
            coords[min(coords.count - 1, Int((Double(i) * step).rounded()))]
        }
    }
}
