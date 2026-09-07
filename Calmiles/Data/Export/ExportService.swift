import Foundation
import UIKit

struct ExportService {
    struct Row: Hashable {
        var date: Date
        var start: Date
        var end: Date
        var distanceMeters: Double
        var classification: TripClassification
        var purpose: String
        var notes: String
        var fromAddress: String
        var toAddress: String
        var isManual: Bool
    }

    let unit: DistanceUnit
    let country: CountryCode
    let includeEstimates: Bool

    func makeRows(from trips: [TripEntity]) -> [Row] {
        trips.map {
            Row(
                date: $0.startDate,
                start: $0.startDate,
                end: $0.endDate,
                distanceMeters: $0.distanceMeters,
                classification: $0.classification,
                purpose: $0.purpose,
                notes: $0.notes,
                fromAddress: $0.fromAddress,
                toAddress: $0.toAddress,
                isManual: $0.isManual
            )
        }
    }

    func csv(from trips: [TripEntity]) -> String {
        let rows = makeRows(from: trips)
        var lines: [String] = []
        lines.append("Calmiles Mileage Export")
        lines.append("Estimates labeled as estimates. Not tax advice.")
        lines.append(RatePreset.notTaxAdviceDisclaimer.replacingOccurrences(of: ",", with: ";"))
        lines.append("")
        let header = [
            "Date", "Start", "End", "Duration_min",
            "Distance_\(unit.shortLabel)", "Classification", "From", "To", "Purpose", "Notes",
            "Source", "Estimate_Amount", "Currency", "Rate_Preset"
        ]
        lines.append(header.joined(separator: ","))

        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]

        for row in rows {
            let distance = DistanceCalculator.convert(meters: row.distanceMeters, to: unit)
            let durationMin = Int(row.end.timeIntervalSince(row.start) / 60)
            var estimateAmount = ""
            var currency = ""
            var presetName = ""
            if includeEstimates, row.classification == .business,
               let est = RateEstimator.estimate(distanceMeters: row.distanceMeters, country: country, on: row.date) {
                estimateAmount = "\(est.amount)"
                currency = est.currencyCode
                presetName = est.preset.name + " (estimate)"
            }
            let fields: [String] = [
                df.string(from: row.date),
                df.string(from: row.start),
                df.string(from: row.end),
                "\(durationMin)",
                String(format: "%.3f", distance),
                row.classification.displayName,
                csvEscape(row.fromAddress),
                csvEscape(row.toAddress),
                csvEscape(row.purpose),
                csvEscape(row.notes),
                row.isManual ? "manual" : "auto",
                estimateAmount,
                currency,
                csvEscape(presetName)
            ]
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    func pdfData(from trips: [TripEntity], title: String = "Calmiles Mileage Log") -> Data {
        let rows = makeRows(from: trips)
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            var y: CGFloat = 0
            func newPage() {
                ctx.beginPage()
                y = 40
                let header = title as NSString
                header.draw(at: CGPoint(x: 40, y: y), withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 18),
                    .foregroundColor: UIColor.label
                ])
                y += 28
                let disclaimer = "ESTIMATES ONLY — NOT TAX ADVICE. " + RatePreset.notTaxAdviceDisclaimer
                let discAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9),
                    .foregroundColor: UIColor.secondaryLabel
                ]
                let discRect = CGRect(x: 40, y: y, width: pageRect.width - 80, height: 60)
                (disclaimer as NSString).draw(in: discRect, withAttributes: discAttr)
                y += 64
            }
            newPage()

            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short

            for row in rows {
                if y > pageRect.height - 100 { newPage() }
                let distance = DistanceCalculator.convert(meters: row.distanceMeters, to: unit)
                var line = "\(df.string(from: row.start))  \(String(format: "%.1f %@", distance, unit.shortLabel))  \(row.classification.displayName)"
                if !row.purpose.isEmpty { line += "  · \(row.purpose)" }
                if includeEstimates, row.classification == .business,
                   let est = RateEstimator.estimate(distanceMeters: row.distanceMeters, country: country, on: row.date) {
                    let amt = RateEstimator.formatAmount(est.amount, currencyCode: est.currencyCode)
                    line += "  · Est. \(amt)"
                }
                (line as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 11),
                    .foregroundColor: UIColor.label
                ])
                y += 16
                let from = row.fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                let to = row.toAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                if !from.isEmpty || !to.isEmpty {
                    let routeLine: String
                    if !from.isEmpty && !to.isEmpty {
                        routeLine = "\(from) → \(to)"
                    } else if !from.isEmpty {
                        routeLine = "From \(from)"
                    } else {
                        routeLine = "To \(to)"
                    }
                    (routeLine as NSString).draw(at: CGPoint(x: 48, y: y), withAttributes: [
                        .font: UIFont.systemFont(ofSize: 9),
                        .foregroundColor: UIColor.secondaryLabel
                    ])
                    y += 14
                }
                y += 4
            }

            if y > pageRect.height - 60 { newPage() }
            ("Generated by Calmiles · Estimates labeled as estimates · Not tax advice" as NSString)
                .draw(at: CGPoint(x: 40, y: pageRect.height - 40), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 8),
                    .foregroundColor: UIColor.tertiaryLabel
                ])
        }
        return data
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
