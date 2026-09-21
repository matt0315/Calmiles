import XCTest
import CoreLocation
import MapKit
@testable import Calmiles

final class GeocodingServiceTests: XCTestCase {
    func testPlaceSearchIncludesAddressesAndPOIs() {
        XCTAssertTrue(GeocodingService.placeSearchResultTypes.contains(.address))
        XCTAssertTrue(GeocodingService.placeSearchResultTypes.contains(.pointOfInterest))
    }

    func testPerthSearchRegionIncludesOptusStadiumAndPemberton() {
        let stadium = CLLocationCoordinate2D(latitude: -31.9512, longitude: 115.8890)
        let pemberton = CLLocationCoordinate2D(latitude: -34.445, longitude: 116.034)
        XCTAssertTrue(GeocodingService.contains(stadium, in: GeocodingService.perthRegion))
        XCTAssertTrue(GeocodingService.contains(pemberton, in: GeocodingService.perthRegion))
        XCTAssertTrue(
            GeocodingService.contains(pemberton, in: GeocodingService.searchRegion(near: GeocodingService.perthCenter)),
            "Typing a South-West locality from Perth must stay inside the completer bias region"
        )
        XCTAssertTrue(GeocodingService.isInAustralia(stadium))
        XCTAssertTrue(GeocodingService.isInAustralia(pemberton))
    }

    func testSuggestionDisplayKeepsVenueName() {
        let display = GeocodingService.displayString(title: "Optus Stadium", subtitle: "Burswood WA")
        XCTAssertTrue(display.localizedCaseInsensitiveContains("Optus Stadium"))
    }
}
