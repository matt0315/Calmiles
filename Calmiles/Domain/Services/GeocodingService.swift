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

    struct ResolvedPlace: Sendable, Equatable {
        var display: String
        var latitude: Double
        var longitude: Double

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    /// Address + POI so stadiums, shops, and named venues resolve — not streets only.
    static let placeSearchResultTypes: MKLocalSearch.ResultType = [.address, .pointOfInterest]

    /// Perth metro — default bias when the user is in WA or we have no better fix.
    static let perthCenter = CLLocationCoordinate2D(latitude: -31.9523, longitude: 115.8613)

    /// ~450 km from Perth: covers the South West (Pemberton, Albany) while still ranking local results first.
    static let perthRegion = MKCoordinateRegion(
        center: perthCenter,
        latitudinalMeters: 900_000,
        longitudinalMeters: 900_000
    )

    /// Rough Australia box used to reject overseas geocodes of local-looking queries.
    static let australiaRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -25.6, longitude: 133.8),
        latitudinalMeters: 3_800_000,
        longitudinalMeters: 4_200_000
    )

    static func searchRegion(near coordinate: CLLocationCoordinate2D?) -> MKCoordinateRegion {
        guard let coordinate, CLLocationCoordinate2DIsValid(coordinate) else {
            return perthRegion
        }
        return MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 900_000,
            longitudinalMeters: 900_000
        )
    }

    /// Forward-geocode a free-form address, biased to Perth / Australia.
    static func coordinate(for address: String, near hint: CLLocationCoordinate2D? = nil) async throws -> CLLocationCoordinate2D {
        let place = try await resolvePlace(address, near: hint)
        return place.coordinate
    }

    /// Resolve an address to a single place, preferring the bias region then Australia.
    static func resolvePlace(_ address: String, near hint: CLLocationCoordinate2D? = nil) async throws -> ResolvedPlace {
        let trimmed = normalizeQuery(address)
        guard !trimmed.isEmpty else { throw GeocodeError.emptyAddress }

        let primary = searchRegion(near: hint)
        // Don't requireIn the bias region: localities like Pemberton sit outside a tight Perth box.
        if let place = await searchPlace(trimmed, region: primary, requireIn: nil),
           isInAustralia(place.coordinate) {
            return place
        }
        if let place = await searchPlace(trimmed, region: australiaRegion, requireIn: australiaRegion) {
            return place
        }
        // Last resort: same query with an Australia hint, still prefer AU results.
        let hinted = trimmed.localizedCaseInsensitiveContains("australia") ? trimmed : trimmed + ", Australia"
        if let place = await searchPlace(hinted, region: australiaRegion, requireIn: nil),
           isInAustralia(place.coordinate) {
            return place
        }
        throw GeocodeError.notFound
    }

    /// Resolve a completer suggestion to a coordinate (region-biased).
    @MainActor
    static func resolve(completion: MKLocalSearchCompletion, near hint: CLLocationCoordinate2D? = nil) async throws -> ResolvedPlace {
        let request = MKLocalSearch.Request(completion: completion)
        request.region = searchRegion(near: hint)
        // The completion already carries its type. Forcing .address drops stadiums / POIs.
        if var place = await firstPlace(from: request, requireIn: nil) {
            let suggestion = displayString(title: completion.title, subtitle: completion.subtitle)
            if !suggestion.isEmpty {
                place.display = suggestion
            }
            return place
        }
        let query = displayString(title: completion.title, subtitle: completion.subtitle)
        return try await resolvePlace(query, near: hint)
    }

    static func displayString(title: String, subtitle: String) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if subtitle.isEmpty { return title }
        if title.localizedCaseInsensitiveContains(subtitle) { return title }
        return "\(title), \(subtitle)"
    }

    /// Geocode From/To and request MapKit automobile directions.
    /// Prefer already-resolved coordinates from autocomplete; otherwise search with a Perth/AU bias.
    /// Never returns a straight-line chord between geocodes — that path drew inland→ocean lines
    /// when unbounded CLGeocoder matched the wrong Moojebing / Jindalee.
    static func directionsRoute(
        from fromAddress: String,
        to toAddress: String,
        startDate: Date,
        fromPlace: ResolvedPlace? = nil,
        toPlace: ResolvedPlace? = nil,
        near hint: CLLocationCoordinate2D? = nil
    ) async throws -> RoutedJourney {
        let fromTrimmed = fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let toTrimmed = toAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fromTrimmed.isEmpty, !toTrimmed.isEmpty else { throw GeocodeError.emptyAddress }

        let startPlace: ResolvedPlace
        if let fromPlace, placesMatch(fromPlace, query: fromTrimmed) {
            startPlace = fromPlace
        } else {
            startPlace = try await resolvePlace(fromTrimmed, near: hint)
        }

        let endHint = hint ?? startPlace.coordinate
        let endPlace: ResolvedPlace
        if let toPlace, placesMatch(toPlace, query: toTrimmed) {
            endPlace = toPlace
        } else {
            endPlace = try await resolvePlace(toTrimmed, near: endHint)
        }

        return try await directionsRoute(from: startPlace, to: endPlace, startDate: startDate)
    }

    static func directionsRoute(
        from startPlace: ResolvedPlace,
        to endPlace: ResolvedPlace,
        startDate: Date
    ) async throws -> RoutedJourney {
        let request = MKDirections.Request()
        request.source = mapItem(for: startPlace)
        request.destination = mapItem(for: endPlace)
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
        // A two-point chord is the old geodesic fallback, not a road. Reject it.
        if coords.count < 3, route.distance > 800 {
            throw GeocodeError.routeUnavailable
        }

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
        startDate: Date,
        fromPlace: ResolvedPlace? = nil,
        toPlace: ResolvedPlace? = nil,
        near hint: CLLocationCoordinate2D? = nil
    ) async -> RoutedJourney? {
        do {
            return try await directionsRoute(
                from: fromAddress,
                to: toAddress,
                startDate: startDate,
                fromPlace: fromPlace,
                toPlace: toPlace,
                near: hint
            )
        } catch {
            return nil
        }
    }

    // MARK: - Search

    private static func searchPlace(
        _ query: String,
        region: MKCoordinateRegion,
        requireIn: MKCoordinateRegion?
    ) async -> ResolvedPlace? {
        let attempts: [MKLocalSearch.ResultType?] = [
            placeSearchResultTypes,
            nil
        ]
        for types in attempts {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = region
            if let types {
                request.resultTypes = types
            }
            if let place = await firstPlace(from: request, requireIn: requireIn) {
                return place
            }
        }
        return nil
    }

    private static func firstPlace(
        from request: MKLocalSearch.Request,
        requireIn: MKCoordinateRegion?
    ) async -> ResolvedPlace? {
        let search = MKLocalSearch(request: request)
        let response: MKLocalSearch.Response
        do {
            response = try await search.start()
        } catch {
            return nil
        }
        let items = response.mapItems.filter { item in
            let coord = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(coord) else { return false }
            if let requireIn, !regionContains(coord, in: requireIn) { return false }
            return true
        }
        guard let item = items.first else { return nil }
        return place(from: item, fallbackQuery: request.naturalLanguageQuery ?? "")
    }

    private static func place(from item: MKMapItem, fallbackQuery: String) -> ResolvedPlace {
        let coord = item.placemark.coordinate
        let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let locality = item.placemark.locality?.trimmingCharacters(in: .whitespacesAndNewlines)
        let area = item.placemark.administrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines)
        let streetParts = [
            item.placemark.subThoroughfare,
            item.placemark.thoroughfare
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        let display: String
        if let name, !name.isEmpty {
            // Prefer venue / locality names (Optus Stadium, Pemberton) over street-only formatting.
            var parts = [name]
            if let locality, !name.localizedCaseInsensitiveContains(locality) {
                parts.append(locality)
            }
            if let area, !parts.joined(separator: " ").localizedCaseInsensitiveContains(area) {
                parts.append(area)
            }
            display = parts.joined(separator: ", ")
        } else if !streetParts.isEmpty {
            var parts = streetParts
            if let locality { parts.append(locality) }
            if let area { parts.append(area) }
            display = parts.joined(separator: ", ")
        } else {
            display = fallbackQuery
        }
        return ResolvedPlace(display: display, latitude: coord.latitude, longitude: coord.longitude)
    }

    private static func mapItem(for place: ResolvedPlace) -> MKMapItem {
        MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
    }

    private static func placesMatch(_ place: ResolvedPlace, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let d = place.display.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty || d.isEmpty { return false }
        if q == d { return true }
        // User kept the string we wrote from the suggestion, possibly with extra country text.
        return d.hasPrefix(q) || q.hasPrefix(d) || q.contains(d) || d.contains(q)
    }

    static func normalizeQuery(_ address: String) -> String {
        var trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        // "Wa" is easy for CLGeocoder to read as Washington. Prefer Western Australia.
        trimmed = trimmed.replacingOccurrences(
            of: #"\bWa\b"#,
            with: "WA",
            options: .regularExpression
        )
        return trimmed
    }

    static func isInAustralia(_ coordinate: CLLocationCoordinate2D) -> Bool {
        regionContains(coordinate, in: australiaRegion)
    }

    static func contains(_ coordinate: CLLocationCoordinate2D, in region: MKCoordinateRegion) -> Bool {
        regionContains(coordinate, in: region)
    }

    private static func regionContains(_ coordinate: CLLocationCoordinate2D, in region: MKCoordinateRegion) -> Bool {
        let lat = abs(coordinate.latitude - region.center.latitude)
        let lon = abs(coordinate.longitude - region.center.longitude)
        return lat <= region.span.latitudeDelta / 2 && lon <= region.span.longitudeDelta / 2
    }

    private static func polylineCoordinates(_ polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        let count = polyline.pointCount
        guard count > 0 else { return [] }
        var coords = Array(repeating: kCLLocationCoordinate2DInvalid, count: count)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
        let valid = coords.filter { CLLocationCoordinate2DIsValid($0) }
        // Cap stored points so SwiftData blobs stay reasonable on long drives.
        let maxPoints = 200
        if valid.count <= maxPoints { return valid }
        let step = Double(valid.count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { i in
            valid[min(valid.count - 1, Int((Double(i) * step).rounded()))]
        }
    }
}
