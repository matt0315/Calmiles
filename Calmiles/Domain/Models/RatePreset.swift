import Foundation

/// Dated mileage rate constants. Estimates only — not tax advice.
struct RatePreset: Identifiable, Hashable, Sendable {
    let id: String
    let country: CountryCode
    let name: String
    let effectiveFrom: Date
    let effectiveTo: Date?
    /// Rate in local currency per mile (US) or per km (AU/UK/CA) as published for that table.
    let ratePerUnit: Decimal
    let unit: DistanceUnit
    let notes: String

    static let notTaxAdviceDisclaimer =
        "Rates are published reference presets for estimates only. Not tax advice. Calmiles does not provide tax advice. Confirm current rates and eligibility with a qualified tax professional or the relevant authority (IRS, ATO, HMRC, CRA)."
}

enum RateTable {
    /// Calendar helper — year-month-day in Gregorian UTC noon to avoid DST edge issues.
    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.calendar = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return c.date ?? Date(timeIntervalSince1970: 0)
    }

    /// IRS standard mileage rate (business) — cents/mile converted to dollars/mile.
    /// Source: IRS IR-2024-312 / prior notices. Verify before filing.
    static let presets: [RatePreset] = [
        RatePreset(
            id: "irs-2025-business",
            country: .us,
            name: "IRS Standard Mileage (Business)",
            effectiveFrom: date(2025, 1, 1),
            effectiveTo: date(2025, 12, 31),
            ratePerUnit: Decimal(string: "0.70")!,
            unit: .miles,
            notes: "2025 IRS standard mileage rate for business use — estimate only."
        ),
        RatePreset(
            id: "irs-2024-business",
            country: .us,
            name: "IRS Standard Mileage (Business)",
            effectiveFrom: date(2024, 1, 1),
            effectiveTo: date(2024, 12, 31),
            ratePerUnit: Decimal(string: "0.67")!,
            unit: .miles,
            notes: "2024 IRS standard mileage rate for business use — estimate only."
        ),
        RatePreset(
            id: "ato-2024-25-cents",
            country: .au,
            name: "ATO Cents per Kilometre",
            effectiveFrom: date(2024, 7, 1),
            effectiveTo: date(2025, 6, 30),
            ratePerUnit: Decimal(string: "0.88")!,
            unit: .kilometers,
            notes: "ATO cents-per-kilometre method 2024–25 — estimate only; annual claim caps may apply."
        ),
        RatePreset(
            id: "ato-2025-26-cents",
            country: .au,
            name: "ATO Cents per Kilometre",
            effectiveFrom: date(2025, 7, 1),
            effectiveTo: date(2026, 6, 30),
            ratePerUnit: Decimal(string: "0.88")!,
            unit: .kilometers,
            notes: "ATO cents-per-kilometre method 2025–26 (verify) — estimate only."
        ),
        RatePreset(
            id: "hmrc-2024-25-first10k",
            country: .uk,
            name: "HMRC Approved Mileage (first 10,000 mi)",
            effectiveFrom: date(2024, 4, 6),
            effectiveTo: date(2025, 4, 5),
            ratePerUnit: Decimal(string: "0.45")!,
            unit: .miles,
            notes: "HMRC AMAP cars/vans first 10,000 business miles — estimate only."
        ),
        RatePreset(
            id: "hmrc-2025-26-first10k",
            country: .uk,
            name: "HMRC Approved Mileage (first 10,000 mi)",
            effectiveFrom: date(2025, 4, 6),
            effectiveTo: date(2026, 4, 5),
            ratePerUnit: Decimal(string: "0.45")!,
            unit: .miles,
            notes: "HMRC AMAP cars/vans first 10,000 business miles — estimate only."
        ),
        RatePreset(
            id: "cra-2025-first5k",
            country: .ca,
            name: "CRA Automobile Allowance (first 5,000 km)",
            effectiveFrom: date(2025, 1, 1),
            effectiveTo: date(2025, 12, 31),
            ratePerUnit: Decimal(string: "0.72")!,
            unit: .kilometers,
            notes: "CRA reasonable per-kilometre allowance 2025 first 5,000 km — estimate only."
        ),
        RatePreset(
            id: "cra-2024-first5k",
            country: .ca,
            name: "CRA Automobile Allowance (first 5,000 km)",
            effectiveFrom: date(2024, 1, 1),
            effectiveTo: date(2024, 12, 31),
            ratePerUnit: Decimal(string: "0.70")!,
            unit: .kilometers,
            notes: "CRA reasonable per-kilometre allowance 2024 first 5,000 km — estimate only."
        ),
    ]

    static func presets(for country: CountryCode, on date: Date = Date()) -> [RatePreset] {
        presets.filter { $0.country == country && $0.effectiveFrom <= date && ($0.effectiveTo == nil || date <= ($0.effectiveTo ?? .distantFuture)) }
    }

    static func activePreset(for country: CountryCode, on date: Date = Date()) -> RatePreset? {
        presets(for: country, on: date).sorted { $0.effectiveFrom > $1.effectiveFrom }.first
            ?? presets.filter { $0.country == country }.sorted { $0.effectiveFrom > $1.effectiveFrom }.first
    }
}
