import XCTest
@testable import Calmiles

final class ClassificationServiceTests: XCTestCase {
    func testClassifyReplacesValue() {
        XCTAssertEqual(
            ClassificationService.classify(.undecided, as: .business),
            .business
        )
        XCTAssertEqual(
            ClassificationService.classify(.business, as: .personal),
            .personal
        )
    }

    func testBusinessCountsTowardReimbursement() {
        XCTAssertTrue(ClassificationService.countsTowardReimbursement(.business))
        XCTAssertFalse(ClassificationService.countsTowardReimbursement(.personal))
        XCTAssertFalse(ClassificationService.countsTowardReimbursement(.undecided))
    }

    func testLabels() {
        XCTAssertEqual(ClassificationService.label(for: .business), "Business")
        XCTAssertEqual(TripClassification.allCases.count, 3)
    }
}
