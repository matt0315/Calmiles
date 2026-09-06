import Foundation

struct RateEstimate: Hashable, Sendable {
    let distanceInRateUnit: Double
    let ratePerUnit: Decimal
    let amount: Decimal
    let currencyCode: String
    let preset: RatePreset
    let isEstimate: Bool

    var disclaimer: String { RatePreset.notTaxAdviceDisclaimer }
}

enum RateEstimator {
    /// Estimate reimbursement using a rate preset. Distance is in meters.
    static func estimate(
        distanceMeters: Double,
        country: CountryCode,
        on date: Date = Date(),
        preset: RatePreset? = nil
    ) -> RateEstimate? {
        guard let preset = preset ?? RateTable.activePreset(for: country, on: date) else { return nil }
        let distanceInUnit = DistanceCalculator.convert(meters: distanceMeters, to: preset.unit)
        let amount = Decimal(distanceInUnit) * preset.ratePerUnit
        return RateEstimate(
            distanceInRateUnit: distanceInUnit,
            ratePerUnit: preset.ratePerUnit,
            amount: amount,
            currencyCode: country.currencyCode,
            preset: preset,
            isEstimate: true
        )
    }

    static func formatAmount(_ amount: Decimal, currencyCode: String, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = locale
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount) \(currencyCode)"
    }
}
