import Foundation

struct AppSettings: Codable, Equatable, Sendable {
    var country: CountryCode
    var distanceUnit: DistanceUnit
    var selectedRatePresetID: String?
    var hasCompletedOnboarding: Bool
    var autoDetectEnabled: Bool
    var freeAutoTripsUsedThisMonth: Int
    var freeTierMonthKey: String // "yyyy-MM"

    static let freeAutoTripLimit = 40

    static var currentMonthKey: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }

    static let `default` = AppSettings(
        country: .us,
        distanceUnit: .miles,
        selectedRatePresetID: nil,
        hasCompletedOnboarding: false,
        autoDetectEnabled: true,
        freeAutoTripsUsedThisMonth: 0,
        freeTierMonthKey: currentMonthKey
    )

    mutating func rolloverFreeTierIfNeeded() {
        let key = Self.currentMonthKey
        if freeTierMonthKey != key {
            freeTierMonthKey = key
            freeAutoTripsUsedThisMonth = 0
        }
    }

    var remainingFreeAutoTrips: Int {
        max(0, Self.freeAutoTripLimit - freeAutoTripsUsedThisMonth)
    }
}
