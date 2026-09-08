import Foundation
import MapKit
import Combine

/// MapKit address completer biased toward Perth / the user's last fix.
@MainActor
final class AddressSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var suggestions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()
    private var hint: CLLocationCoordinate2D?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address]
        completer.region = GeocodingService.perthRegion
    }

    func setHint(_ coordinate: CLLocationCoordinate2D?) {
        hint = coordinate
        completer.region = GeocodingService.searchRegion(near: coordinate)
    }

    func updateQuery(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            suggestions = []
            completer.queryFragment = ""
            return
        }
        completer.region = GeocodingService.searchRegion(near: hint)
        completer.queryFragment = query
    }

    func clear() {
        suggestions = []
        completer.queryFragment = ""
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = Array(completer.results.prefix(6))
        Task { @MainActor in
            self.suggestions = results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            // Keep the last good list; empty queries already clear it.
            if completer.queryFragment.isEmpty {
                self.suggestions = []
            }
        }
    }
}
