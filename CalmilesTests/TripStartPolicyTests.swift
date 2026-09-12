import XCTest
@testable import Calmiles

final class TripStartPolicyTests: XCTestCase {
    func testBackfillPrependsRecentParkWhenWakeIsLate() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let anchor = TripStartPolicy.Anchor(
            latitude: -31.92,
            longitude: 115.91,
            timestamp: start,
            horizontalAccuracy: 30
        )
        // ~1.1 km north, 8 minutes later — a missed first half, still a plausible drive.
        let wake = CoordinatePoint(
            latitude: -31.910,
            longitude: 115.91,
            timestamp: start.addingTimeInterval(8 * 60),
            speed: nil,
            horizontalAccuracy: 80
        )
        let filled = TripStartPolicy.backfillStart(anchor: anchor, firstMoving: wake)
        XCTAssertNotNil(filled)
        XCTAssertEqual(filled?.latitude ?? 0, anchor.latitude, accuracy: 0.0001)
        XCTAssertEqual(filled?.timestamp, start)
    }

    func testBackfillRejectsStaleOrImpossibleJump() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let anchor = TripStartPolicy.Anchor(
            latitude: -31.92,
            longitude: 115.91,
            timestamp: start,
            horizontalAccuracy: 20
        )
        let stale = CoordinatePoint(
            latitude: -31.90,
            longitude: 115.91,
            timestamp: start.addingTimeInterval(70 * 60)
        )
        XCTAssertNil(TripStartPolicy.backfillStart(anchor: anchor, firstMoving: stale))

        // Hundreds of km in two minutes is a bad fix, not a departure.
        let jump = CoordinatePoint(
            latitude: -28.0,
            longitude: 115.91,
            timestamp: start.addingTimeInterval(120)
        )
        XCTAssertNil(TripStartPolicy.backfillStart(anchor: anchor, firstMoving: jump))
    }

    func testDepartureDoesNotRequireValidSpeed() {
        let start = Date()
        let anchor = TripStartPolicy.Anchor(
            latitude: -31.95,
            longitude: 115.86,
            timestamp: start,
            horizontalAccuracy: 25
        )
        // Speed invalid (-1 is filtered to not "moving"), but the phone is already ~400m away.
        let left = TripStartPolicy.hasDeparted(
            anchor: anchor,
            latitude: -31.946,
            longitude: 115.86,
            speed: -1,
            timestamp: start.addingTimeInterval(90)
        )
        XCTAssertTrue(left)

        let stillThere = TripStartPolicy.hasDeparted(
            anchor: anchor,
            latitude: -31.9502,
            longitude: 115.8602,
            speed: -1,
            timestamp: start.addingTimeInterval(30)
        )
        XCTAssertFalse(stillThere)
    }

    func testDwellEndsAwayFromOriginPark() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        // Drive ~5 km north, then sit still at the destination for 3+ minutes.
        var points: [CoordinatePoint] = [
            .init(latitude: -31.95, longitude: 115.86, timestamp: t0, speed: 0),
            .init(latitude: -31.92, longitude: 115.86, timestamp: t0.addingTimeInterval(600), speed: 12),
            .init(latitude: -31.90, longitude: 115.86, timestamp: t0.addingTimeInterval(900), speed: 10),
        ]
        let destLat = -31.90
        let destLon = 115.86
        let parkStart = t0.addingTimeInterval(960)
        for i in 0..<6 {
            points.append(
                .init(
                    latitude: destLat + Double(i) * 0.00001,
                    longitude: destLon,
                    timestamp: parkStart.addingTimeInterval(Double(i) * 35),
                    speed: 0.2
                )
            )
        }
        let now = points.last!.timestamp.addingTimeInterval(5)
        XCTAssertTrue(
            TripStartPolicy.isStationaryDwell(points: points, now: now),
            "A parked destination far from home must end the trip via dwell, not only visit callbacks"
        )
    }

    func testDwellDoesNotFireWhileStillDriving() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let points: [CoordinatePoint] = (0..<8).map { i in
            CoordinatePoint(
                latitude: -31.95 + Double(i) * 0.002,
                longitude: 115.86,
                timestamp: t0.addingTimeInterval(Double(i) * 40),
                speed: 11
            )
        }
        XCTAssertFalse(
            TripStartPolicy.isStationaryDwell(points: points, now: points.last!.timestamp),
            "Moving samples must not look like a dwell"
        )
    }
}
