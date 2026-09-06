import Foundation

enum ClassificationService {
    /// Apply a one-tap classification. Pure domain helper for tests and UI.
    static func classify(_ current: TripClassification, as next: TripClassification) -> TripClassification {
        next
    }

    static func isBusiness(_ classification: TripClassification) -> Bool {
        classification == .business
    }

    static func countsTowardReimbursement(_ classification: TripClassification) -> Bool {
        classification == .business
    }

    static func label(for classification: TripClassification) -> String {
        classification.displayName
    }
}
