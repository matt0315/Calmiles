import Foundation

/// App Group shared defaults for WidgetKit. Falls back to standard defaults if group missing.
enum WidgetSharedStore {
    static let appGroupID = "group.studio.botland.calmiles"
    static let summaryKey = "widget.weeklySummary"

    struct Snapshot: Codable, Hashable {
        var weekLabel: String
        var tripCount: Int
        var businessDistanceText: String
        var estimateText: String
        var remainingFreeTrips: Int
        var updatedAt: Date
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func write(_ snapshot: Snapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: summaryKey)
        }
    }

    static func read() -> Snapshot? {
        guard let data = defaults.data(forKey: summaryKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    @MainActor
    static func writeSummary(from settings: AppSettings) {
        // Lightweight placeholder until home refresh writes fuller stats.
        let snap = Snapshot(
            weekLabel: "This week",
            tripCount: 0,
            businessDistanceText: "—",
            estimateText: "Estimate",
            remainingFreeTrips: settings.remainingFreeAutoTrips,
            updatedAt: Date()
        )
        if read() == nil {
            write(snap)
        }
    }

    static func writeWeekly(
        summary: WeeklySummary,
        unit: DistanceUnit,
        estimateText: String,
        remainingFree: Int
    ) {
        let business = DistanceCalculator.convert(meters: summary.businessMeters, to: unit)
        let distanceText = String(format: "%.1f %@", business, unit.shortLabel)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let label = "Week of \(formatter.string(from: summary.weekStart))"
        write(Snapshot(
            weekLabel: label,
            tripCount: summary.tripCount,
            businessDistanceText: distanceText,
            estimateText: estimateText,
            remainingFreeTrips: remainingFree,
            updatedAt: Date()
        ))
    }
}
