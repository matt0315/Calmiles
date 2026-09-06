import XCTest
@testable import Calmiles

final class DistanceCalculatorTests: XCTestCase {
    func testHaversineKnownShortDistance() {
        // ~1 km north-south near equator approximation
        let a = CoordinatePoint(latitude: 0, longitude: 0)
        let b = CoordinatePoint(latitude: 0.009, longitude: 0) // ~1 km
        let meters = DistanceCalculator.haversineMeters(from: a, to: b)
        XCTAssertEqual(meters, 1000, accuracy: 50)
    }

    func testPathLengthSumsSegments() {
        let points = [
            CoordinatePoint(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
            CoordinatePoint(latitude: 37.7759, longitude: -122.4194, timestamp: Date().addingTimeInterval(60)),
            CoordinatePoint(latitude: 37.7769, longitude: -122.4194, timestamp: Date().addingTimeInterval(120)),
        ]
        let meters = DistanceCalculator.pathLengthMeters(points)
        XCTAssertGreaterThan(meters, 150)
        XCTAssertLessThan(meters, 300)
    }

    func testUnitConversionRoundTrip() {
        let miles = 10.0
        let meters = DistanceCalculator.milesToMeters(miles)
        let back = DistanceCalculator.metersToMiles(meters)
        XCTAssertEqual(back, miles, accuracy: 0.0001)

        let km = DistanceCalculator.convert(value: miles, from: .miles, to: .kilometers)
        XCTAssertEqual(km, miles * 1.609344, accuracy: 0.001)
    }

    func testEmptyPathIsZero() {
        XCTAssertEqual(DistanceCalculator.pathLengthMeters([]), 0)
        XCTAssertEqual(DistanceCalculator.pathLengthMeters([.init(latitude: 1, longitude: 1)]), 0)
    }
}
