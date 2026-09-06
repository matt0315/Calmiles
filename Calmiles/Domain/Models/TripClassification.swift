import Foundation

enum TripClassification: String, Codable, CaseIterable, Identifiable, Sendable {
    case business
    case personal
    case undecided

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .business: return "Business"
        case .personal: return "Personal"
        case .undecided: return "Undecided"
        }
    }
}
