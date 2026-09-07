import SwiftUI

struct TripRowView: View {
    let trip: TripEntity
    let unit: DistanceUnit

    var body: some View {
        CalmilesCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(trip.startDate, style: .date)
                        .font(CalmilesTypography.headline)
                        .foregroundStyle(Color.calmilesPrimaryText)
                    Text(timeRange)
                        .font(CalmilesTypography.caption)
                        .foregroundStyle(Color.calmilesSecondaryText)
                    if let route = trip.routeLabel {
                        Text(route)
                            .font(CalmilesTypography.callout)
                            .foregroundStyle(Color.calmilesSecondaryText)
                            .lineLimit(2)
                    } else if !trip.purpose.isEmpty {
                        Text(trip.purpose)
                            .font(CalmilesTypography.callout)
                            .foregroundStyle(Color.calmilesSecondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(distanceText)
                        .font(CalmilesTypography.headline.monospacedDigit())
                        .foregroundStyle(Color.calmilesPrimaryText)
                    ClassificationChip(classification: trip.classification, isSelected: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var distanceText: String {
        let v = DistanceCalculator.convert(meters: trip.distanceMeters, to: unit)
        return String(format: "%.1f %@", v, unit.shortLabel)
    }

    private var timeRange: String {
        let f = DateFormatter()
        f.timeStyle = .short
        return "\(f.string(from: trip.startDate)) – \(f.string(from: trip.endDate))"
    }

    private var accessibilityLabel: String {
        var parts = ["\(trip.classification.displayName) trip", distanceText, trip.startDate.formatted()]
        if let route = trip.routeLabel {
            parts.append(route)
        }
        return parts.joined(separator: ", ")
    }
}
