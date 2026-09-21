import Foundation

enum CountryCode: String, Codable, CaseIterable, Identifiable, Sendable {
    case us = "US"
    case au = "AU"
    case uk = "UK"
    case ca = "CA"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .us: return "United States"
        case .au: return "Australia"
        case .uk: return "United Kingdom"
        case .ca: return "Canada"
        }
    }

    var authorityName: String {
        switch self {
        case .us: return "IRS"
        case .au: return "ATO"
        case .uk: return "HMRC"
        case .ca: return "CRA"
        }
    }

    var defaultDistanceUnit: DistanceUnit {
        switch self {
        case .us: return .miles
        case .au, .uk, .ca: return .kilometers
        }
    }

    var currencyCode: String {
        switch self {
        case .us: return "USD"
        case .au: return "AUD"
        case .uk: return "GBP"
        case .ca: return "CAD"
        }
    }
}

enum DistanceUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case miles
    case kilometers

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .miles: return "mi"
        case .kilometers: return "km"
        }
    }

    var displayName: String {
        switch self {
        case .miles: return "Miles"
        case .kilometers: return "Kilometers"
        }
    }
}
