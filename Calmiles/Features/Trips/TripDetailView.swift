import SwiftUI
import MapKit

struct TripDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: SettingsStore
    @Bindable var trip: TripEntity
    @State private var showEdit = false
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                mapSection
                statsSection
                classifySection
                purposeSection
                estimateSection
            }
            .padding()
        }
        .background(Color.calmilesBackground.ignoresSafeArea())
        .navigationTitle("Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            TripEditView(mode: .edit(trip))
        }
        .onAppear {
            AnalyticsStub.screen("trip_detail")
            updateCamera()
        }
    }

    @ViewBuilder
    private var mapSection: some View {
        let coords = trip.routePoints
        if coords.count >= 2 {
            Map(position: $cameraPosition) {
                MapPolyline(coordinates: coords.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                })
                .stroke(CalmilesColor.copper, lineWidth: 4)
                if let first = coords.first, let last = coords.last {
                    Annotation("Start", coordinate: .init(latitude: first.latitude, longitude: first.longitude)) {
                        Image(systemName: "circle.fill").foregroundStyle(CalmilesColor.success)
                    }
                    Annotation("End", coordinate: .init(latitude: last.latitude, longitude: last.longitude)) {
                        Image(systemName: "flag.fill").foregroundStyle(CalmilesColor.danger)
                    }
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("Trip route map")
        } else {
            CalmilesCard {
                Label("No route polyline for this trip", systemImage: "map")
                    .foregroundStyle(Color.calmilesSecondaryText)
            }
        }
    }

    private var statsSection: some View {
        CalmilesCard {
            VStack(alignment: .leading, spacing: 8) {
                labeled("Distance", distanceText)
                labeled("Duration", durationText)
                labeled("When", trip.startDate.formatted(date: .abbreviated, time: .shortened)
                        + " – " + trip.endDate.formatted(date: .omitted, time: .shortened))
                labeled("Source", trip.isManual ? "Manual" : "Auto-detected")
            }
        }
    }

    private var classifySection: some View {
        CalmilesCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Classify")
                    .font(CalmilesTypography.headline)
                    .foregroundStyle(Color.calmilesPrimaryText)
                HStack(spacing: 8) {
                    ForEach(TripClassification.allCases) { c in
                        ClassificationChip(classification: c, isSelected: trip.classification == c) {
                            trip.classification = ClassificationService.classify(trip.classification, as: c)
                            save()
                            AnalyticsStub.log("trip_classified", ["to": c.rawValue])
                        }
                    }
                }
            }
        }
    }

    private var purposeSection: some View {
        CalmilesCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Purpose")
                    .font(CalmilesTypography.headline)
                Text(trip.purpose.isEmpty ? "—" : trip.purpose)
                    .foregroundStyle(Color.calmilesSecondaryText)
                if !trip.notes.isEmpty {
                    Text(trip.notes)
                        .font(CalmilesTypography.callout)
                        .foregroundStyle(Color.calmilesSecondaryText)
                }
            }
        }
    }

    private var estimateSection: some View {
        Group {
            if trip.classification == .business,
               let est = RateEstimator.estimate(distanceMeters: trip.distanceMeters, country: settings.settings.country, on: trip.startDate) {
                CalmilesCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Estimate")
                            .font(CalmilesTypography.headline)
                        Text(RateEstimator.formatAmount(est.amount, currencyCode: est.currencyCode))
                            .font(CalmilesTypography.metric)
                            .foregroundStyle(CalmilesColor.copper)
                        Text(est.preset.name)
                            .font(CalmilesTypography.caption)
                            .foregroundStyle(Color.calmilesSecondaryText)
                        Text("Estimate only — not tax advice.")
                            .font(CalmilesTypography.caption)
                            .foregroundStyle(CalmilesColor.danger.opacity(0.9))
                    }
                }
            }
        }
    }

    private var distanceText: String {
        let v = DistanceCalculator.convert(meters: trip.distanceMeters, to: settings.settings.distanceUnit)
        return String(format: "%.2f %@", v, settings.settings.distanceUnit.shortLabel)
    }

    private var durationText: String {
        let m = Int(trip.duration / 60)
        let h = m / 60
        let rem = m % 60
        return h > 0 ? "\(h)h \(rem)m" : "\(rem) min"
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Color.calmilesSecondaryText)
            Spacer()
            Text(value).foregroundStyle(Color.calmilesPrimaryText)
        }
        .font(CalmilesTypography.body)
    }

    private func save() {
        do { try TripRepository(context: modelContext).update(trip) }
        catch { CrashProtocolStub.record(error) }
    }

    private func updateCamera() {
        let coords = trip.routePoints
        guard let first = coords.first else { return }
        if coords.count == 1 {
            cameraPosition = .region(MKCoordinateRegion(
                center: .init(latitude: first.latitude, longitude: first.longitude),
                span: .init(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ))
            return
        }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        cameraPosition = .region(MKCoordinateRegion(
            center: center,
            span: .init(latitudeDelta: max(0.02, (maxLat - minLat) * 1.4),
                        longitudeDelta: max(0.02, (maxLon - minLon) * 1.4))
        ))
    }
}
