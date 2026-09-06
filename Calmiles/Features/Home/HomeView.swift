import SwiftUI
import SwiftData
import WidgetKit

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @Query(sort: \TripEntity.startDate, order: .reverse) private var trips: [TripEntity]

    @State private var summary: WeeklySummary?
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    weeklyCard
                    freeTierCard
                    recentTrips
                }
                .padding()
            }
            .background(Color.calmilesBackground.ignoresSafeArea())
            .navigationTitle("Calmiles")
            .toolbar {
                #if DEBUG
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sample") {
                        TripDetectionService.shared.injectSampleTrip()
                    }
                    .accessibilityLabel("Inject sample trip")
                }
                #endif
            }
            .onAppear {
                AnalyticsStub.screen("home")
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-UITestSeedTrips") {
                    seedUITestTripsIfNeeded()
                }
                #endif
                refreshSummary()
            }
            .onChange(of: trips.count) { _, _ in refreshSummary() }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    private var weeklyCard: some View {
        CalmilesCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("This week")
                    .font(CalmilesTypography.headline)
                    .foregroundStyle(Color.calmilesPrimaryText)
                if let summary {
                    HStack(spacing: 20) {
                        metric("Trips", "\(summary.tripCount)")
                        metric(settings.settings.distanceUnit.shortLabel,
                               String(format: "%.1f", DistanceCalculator.convert(meters: summary.businessMeters, to: settings.settings.distanceUnit)))
                        metric("Business", "\(summary.businessCount)")
                    }
                    if let est = RateEstimator.estimate(distanceMeters: summary.businessMeters, country: settings.settings.country) {
                        Text("Est. \(RateEstimator.formatAmount(est.amount, currencyCode: est.currencyCode)) · estimate only")
                            .font(CalmilesTypography.caption)
                            .foregroundStyle(Color.calmilesSecondaryText)
                    }
                    if summary.undecidedCount > 0 {
                        Text("\(summary.undecidedCount) undecided — tap to classify")
                            .font(CalmilesTypography.callout)
                            .foregroundStyle(CalmilesColor.copper)
                    }
                } else {
                    Text("No trips yet this week.")
                        .foregroundStyle(Color.calmilesSecondaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(CalmilesTypography.metric)
                .foregroundStyle(Color.calmilesPrimaryText)
            Text(label)
                .font(CalmilesTypography.caption)
                .foregroundStyle(Color.calmilesSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var freeTierCard: some View {
        Group {
            if !subscriptions.isPro {
                CalmilesCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Free auto-trips")
                                .font(CalmilesTypography.headline)
                            Text("\(settings.settings.remainingFreeAutoTrips) of \(AppSettings.freeAutoTripLimit) left this month")
                                .font(CalmilesTypography.callout)
                                .foregroundStyle(Color.calmilesSecondaryText)
                        }
                        Spacer()
                        Button("Upgrade") { showPaywall = true }
                            .font(CalmilesTypography.headline)
                            .foregroundStyle(CalmilesColor.copper)
                    }
                }
            }
        }
    }

    private var recentTrips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(CalmilesTypography.headline)
                .foregroundStyle(Color.calmilesPrimaryText)
            if trips.isEmpty {
                EmptyStateView(
                    title: "No trips yet",
                    message: settings.settings.autoDetectEnabled
                        ? "Drive with location enabled, or add a trip manually."
                        : "Add a trip manually from the Trips tab.",
                    systemImage: "car.side"
                )
            } else {
                ForEach(trips.prefix(5)) { trip in
                    NavigationLink(value: trip.id) {
                        TripRowView(trip: trip, unit: settings.settings.distanceUnit)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationDestination(for: UUID.self) { id in
            if let trip = trips.first(where: { $0.id == id }) {
                TripDetailView(trip: trip)
            }
        }
    }

    private func refreshSummary() {
        let repo = TripRepository(context: modelContext)
        do {
            let s = try repo.weeklySummary()
            summary = s
            let estText: String
            if let est = RateEstimator.estimate(distanceMeters: s.businessMeters, country: settings.settings.country) {
                estText = "Est. " + RateEstimator.formatAmount(est.amount, currencyCode: est.currencyCode)
            } else {
                estText = "Estimate"
            }
            WidgetSharedStore.writeWeekly(
                summary: s,
                unit: settings.settings.distanceUnit,
                estimateText: estText,
                remainingFree: settings.settings.remainingFreeAutoTrips
            )
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            CrashProtocolStub.record(error)
        }
    }

    #if DEBUG
    private func seedUITestTripsIfNeeded() {
        let key = "calmiles.uitest.seeded"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let repo = TripRepository(context: modelContext)
        let now = Date()
        let samples: [(TimeInterval, TripClassification, String)] = [
            (3600, .business, "Client visit"),
            (7200, .undecided, ""),
            (10800, .personal, "Groceries"),
        ]
        for (offset, classification, purpose) in samples {
            let end = now.addingTimeInterval(-offset)
            let start = end.addingTimeInterval(-2400)
            let points: [CoordinatePoint] = [
                .init(latitude: -31.9505, longitude: 115.8605, timestamp: start),
                .init(latitude: -31.9550, longitude: 115.8700, timestamp: start.addingTimeInterval(800)),
                .init(latitude: -31.9600, longitude: 115.8800, timestamp: end),
            ]
            let meters = DistanceCalculator.pathLengthMeters(points)
            let trip = TripEntity(
                startDate: start,
                endDate: end,
                distanceMeters: meters,
                classification: classification,
                purpose: purpose,
                notes: "",
                isManual: true,
                isAutoDetected: false,
                routePoints: points
            )
            try? repo.add(trip)
        }
        UserDefaults.standard.set(true, forKey: key)
        refreshSummary()
        WidgetCenter.shared.reloadAllTimelines()
    }
    #endif

}

extension TripEntity: Identifiable {}
