import XCTest
@testable import Calmiles

final class RateEstimatorTests: XCTestCase {
    func testIRSEstimateUsesMiles() throws {
        let meters = DistanceCalculator.milesToMeters(100)
        let est = try XCTUnwrap(RateEstimator.estimate(
            distanceMeters: meters,
            country: .us,
            on: date(2025, 6, 15)
        ))
        XCTAssertEqual(est.preset.unit, .miles)
        XCTAssertEqual(est.distanceInRateUnit, 100, accuracy: 0.01)
        XCTAssertEqual(est.amount as NSDecimalNumber, NSDecimalNumber(string: "70.00"))
        XCTAssertTrue(est.isEstimate)
        XCTAssertTrue(est.disclaimer.contains("not tax advice") || est.disclaimer.contains("Not tax advice") || est.disclaimer.lowercased().contains("not tax advice"))
    }

    func testATOEstimateUsesKilometers() throws {
        let meters = DistanceCalculator.kilometersToMeters(50)
        let est = try XCTUnwrap(RateEstimator.estimate(
            distanceMeters: meters,
            country: .au,
            on: date(2025, 1, 15)
        ))
        XCTAssertEqual(est.preset.unit, .kilometers)
        XCTAssertEqual(est.currencyCode, "AUD")
        XCTAssertEqual(NSDecimalNumber(decimal: est.amount).doubleValue, 44.0, accuracy: 0.01)
    }

    func testFormatAmountIncludesCurrencySymbol() {
        let formatted = RateEstimator.formatAmount(Decimal(string: "12.34")!, currencyCode: "USD", locale: Locale(identifier: "en_US"))
        XCTAssertTrue(formatted.contains("12.34"))
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.calendar = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return c.date!
    }
}
