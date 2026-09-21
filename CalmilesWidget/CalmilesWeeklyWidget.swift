import WidgetKit
import SwiftUI

struct WeeklyEntry: TimelineEntry {
    let date: Date
    let weekLabel: String
    let tripCount: Int
    let businessDistanceText: String
    let estimateText: String
}

struct WeeklyProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeeklyEntry {
        WeeklyEntry(date: Date(), weekLabel: "This week", tripCount: 3, businessDistanceText: "42.0 mi", estimateText: "Est. $29.40")
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyEntry>) -> Void) {
        let entry = loadEntry()
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> WeeklyEntry {
        let defaults = UserDefaults(suiteName: "group.studio.botland.calmiles") ?? .standard
        if let data = defaults.data(forKey: "widget.weeklySummary"),
           let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) {
            return WeeklyEntry(
                date: Date(),
                weekLabel: snap.weekLabel,
                tripCount: snap.tripCount,
                businessDistanceText: snap.businessDistanceText,
                estimateText: snap.estimateText
            )
        }
        return WeeklyEntry(date: Date(), weekLabel: "This week", tripCount: 0, businessDistanceText: "—", estimateText: "Estimate")
    }
}

/// Mirror of WidgetSharedStore.Snapshot for the extension target (no shared framework).
struct WidgetSnapshot: Codable {
    var weekLabel: String
    var tripCount: Int
    var businessDistanceText: String
    var estimateText: String
    var remainingFreeTrips: Int
    var updatedAt: Date
}

struct CalmilesWeeklyWidget: Widget {
    let kind = "CalmilesWeeklyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeeklyProvider()) { entry in
            WeeklyWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(red: 0x1B / 255, green: 0x24 / 255, blue: 0x36 / 255)
                }
        }
        .configurationDisplayName("Weekly Miles")
        .description("Business mileage summary for the current week.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WeeklyWidgetView: View {
    let entry: WeeklyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Calmiles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0xC4 / 255, green: 0xA5 / 255, blue: 0x74 / 255))
            Text(entry.weekLabel)
                .font(.caption2)
                .foregroundStyle(Color(red: 0xE8 / 255, green: 0xEE / 255, blue: 0xF7 / 255).opacity(0.7))
            Spacer(minLength: 0)
            Text(entry.businessDistanceText)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(Color(red: 0xE8 / 255, green: 0xEE / 255, blue: 0xF7 / 255))
            Text("\(entry.tripCount) trips · \(entry.estimateText)")
                .font(.caption2)
                .foregroundStyle(Color(red: 0xD4 / 255, green: 0xC4 / 255, blue: 0xA8 / 255))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.weekLabel), \(entry.businessDistanceText), \(entry.tripCount) trips, \(entry.estimateText)")
    }
}
