import SwiftUI
import SwiftData
import MapKit

enum TripEditMode {
    case add
    case edit(TripEntity)
}

struct TripEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: SettingsStore

    let mode: TripEditMode

    @State private var startDate = Date().addingTimeInterval(-3600)
    @State private var endDate = Date()
    @State private var fromAddress: String = ""
    @State private var toAddress: String = ""
    @State private var distanceValue: String = "10"
    @State private var classification: TripClassification = .undecided
    @State private var purpose: String = ""
    @State private var notes: String = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    @State private var previewPoints: [CoordinatePoint] = []
    @State private var isRouting = false
    @State private var routeStatusMessage: String?
    @State private var expectedTravelTime: TimeInterval?
    @State private var routeTask: Task<Void, Never>?
    @State private var cameraPosition: MapCameraPosition = .automatic
    /// When true, automatic route fills should not overwrite the user's distance edit.
    @State private var distanceOverridden = false
    /// When true, automatic ETA should not overwrite the user's end-time edit.
    @State private var endOverridden = false
    @State private var suppressOverrideTracking = false
    @State private var lastRoutedFrom = ""
    @State private var lastRoutedTo = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Route") {
                    TextField("From", text: $fromAddress)
                        .textContentType(.fullStreetAddress)
                        .autocorrectionDisabled()
                        .onSubmit { scheduleRouteCalculation(immediate: true) }
                    TextField("To", text: $toAddress)
                        .textContentType(.fullStreetAddress)
                        .autocorrectionDisabled()
                        .onSubmit { scheduleRouteCalculation(immediate: true) }
                    if isRouting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Calculating route…")
                                .foregroundStyle(Color.calmilesSecondaryText)
                        }
                        .font(CalmilesTypography.caption)
                    } else if let routeStatusMessage {
                        Text(routeStatusMessage)
                            .font(CalmilesTypography.caption)
                            .foregroundStyle(
                                routeStatusMessage.hasPrefix("Couldn’t")
                                    ? CalmilesColor.danger
                                    : Color.calmilesSecondaryText
                            )
                    }
                    if !isRouting, canAttemptRoute, previewPoints.count < 2 {
                        Button("Calculate route") {
                            scheduleRouteCalculation(immediate: true)
                        }
                    }
                }

                if previewPoints.count >= 2 {
                    Section("Map") {
                        Map(position: $cameraPosition) {
                            MapPolyline(coordinates: previewPoints.map {
                                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                            })
                            .stroke(CalmilesColor.copper, lineWidth: 4)
                            if let first = previewPoints.first, let last = previewPoints.last {
                                Annotation("Start", coordinate: .init(latitude: first.latitude, longitude: first.longitude)) {
                                    Image(systemName: "circle.fill").foregroundStyle(CalmilesColor.success)
                                }
                                Annotation("End", coordinate: .init(latitude: last.latitude, longitude: last.longitude)) {
                                    Image(systemName: "flag.fill").foregroundStyle(CalmilesColor.danger)
                                }
                            }
                        }
                        .frame(height: 180)
                        .listRowInsets(EdgeInsets())
                        .accessibilityLabel("Trip route preview")
                    }
                }

                Section("When") {
                    DatePicker("Start", selection: $startDate)
                    DatePicker("End", selection: $endDate)
                }
                Section("Distance (\(settings.settings.distanceUnit.shortLabel))") {
                    TextField("Distance", text: $distanceValue)
                        .keyboardType(.decimalPad)
                        .onChange(of: distanceValue) { _, _ in
                            guard !suppressOverrideTracking else { return }
                            if expectedTravelTime != nil || !previewPoints.isEmpty {
                                distanceOverridden = true
                            }
                        }
                }
                Section("Classification") {
                    Picker("Classification", selection: $classification) {
                        ForEach(TripClassification.allCases) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Details") {
                    TextField("Purpose", text: $purpose)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(CalmilesColor.danger)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear(perform: load)
            .onChange(of: fromAddress) { _, _ in scheduleRouteCalculation(immediate: false) }
            .onChange(of: toAddress) { _, _ in scheduleRouteCalculation(immediate: false) }
            .onChange(of: startDate) { _, newStart in
                if !endOverridden, let travel = expectedTravelTime {
                    suppressOverrideTracking = true
                    endDate = newStart.addingTimeInterval(travel)
                    suppressOverrideTracking = false
                    restampPreview(from: newStart, travel: travel)
                }
            }
            .onChange(of: endDate) { _, new in
                guard !suppressOverrideTracking else { return }
                if let travel = expectedTravelTime {
                    let autoEnd = startDate.addingTimeInterval(travel)
                    if abs(new.timeIntervalSince(autoEnd)) > 1.5 {
                        endOverridden = true
                    }
                }
            }
            .onDisappear {
                routeTask?.cancel()
            }
        }
    }

    private var title: String {
        switch mode {
        case .add: return "Add Trip"
        case .edit: return "Edit Trip"
        }
    }

    private var canAttemptRoute: Bool {
        let from = fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = toAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return !from.isEmpty && !to.isEmpty
    }

    private func load() {
        if case .edit(let trip) = mode {
            startDate = trip.startDate
            endDate = trip.endDate
            fromAddress = trip.fromAddress
            toAddress = trip.toAddress
            let v = DistanceCalculator.convert(meters: trip.distanceMeters, to: settings.settings.distanceUnit)
            distanceValue = String(format: "%.2f", v)
            classification = trip.classification
            purpose = trip.purpose
            notes = trip.notes
            previewPoints = trip.routePoints
            updateCamera(with: previewPoints)
            // Existing distance/end are treated as authoritative until addresses change.
            distanceOverridden = true
            endOverridden = true
            lastRoutedFrom = fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            lastRoutedTo = toAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            let travel = trip.endDate.timeIntervalSince(trip.startDate)
            if travel > 0 {
                expectedTravelTime = travel
            }
        }
        if canAttemptRoute {
            scheduleRouteCalculation(immediate: true)
        }
    }

    private func scheduleRouteCalculation(immediate: Bool) {
        routeTask?.cancel()
        let from = fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = toAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else {
            isRouting = false
            routeStatusMessage = nil
            previewPoints = []
            expectedTravelTime = nil
            lastRoutedFrom = ""
            lastRoutedTo = ""
            return
        }
        // Skip if addresses unchanged and we already have a route.
        if from == lastRoutedFrom, to == lastRoutedTo, previewPoints.count >= 2, !immediate {
            return
        }
        // New addresses → allow auto distance / end from the fresh route.
        if from != lastRoutedFrom || to != lastRoutedTo {
            distanceOverridden = false
            endOverridden = false
        }
        routeTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(nanoseconds: 800_000_000)
                if Task.isCancelled { return }
            }
            await calculateRoute()
        }
    }

    @MainActor
    private func calculateRoute() async {
        let from = fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = toAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else { return }

        isRouting = true
        routeStatusMessage = nil
        defer { isRouting = false }

        do {
            let journey = try await GeocodingService.directionsRoute(
                from: from,
                to: to,
                startDate: startDate
            )
            if Task.isCancelled { return }
            previewPoints = journey.points
            expectedTravelTime = journey.expectedTravelTime
            lastRoutedFrom = from
            lastRoutedTo = to
            updateCamera(with: journey.points)

            suppressOverrideTracking = true
            if !distanceOverridden {
                let display = DistanceCalculator.convert(
                    meters: journey.distanceMeters,
                    to: settings.settings.distanceUnit
                )
                distanceValue = String(format: "%.2f", display)
            }
            if !endOverridden {
                endDate = startDate.addingTimeInterval(journey.expectedTravelTime)
            }
            suppressOverrideTracking = false
            let distLabel = String(
                format: "%.1f %@",
                DistanceCalculator.convert(meters: journey.distanceMeters, to: settings.settings.distanceUnit),
                settings.settings.distanceUnit.shortLabel
            )
            let mins = Int((journey.expectedTravelTime / 60).rounded())
            routeStatusMessage = "Route ready · \(distLabel) · ~\(mins) min"
        } catch {
            if Task.isCancelled { return }
            previewPoints = []
            expectedTravelTime = nil
            lastRoutedFrom = ""
            lastRoutedTo = ""
            routeStatusMessage = "Couldn’t calculate a driving route for these addresses."
        }
    }

    private func restampPreview(from start: Date, travel: TimeInterval) {
        guard previewPoints.count >= 2 else { return }
        let count = previewPoints.count
        previewPoints = previewPoints.enumerated().map { index, point in
            let fraction = Double(index) / Double(count - 1)
            return CoordinatePoint(
                latitude: point.latitude,
                longitude: point.longitude,
                timestamp: start.addingTimeInterval(travel * fraction),
                speed: point.speed,
                horizontalAccuracy: point.horizontalAccuracy
            )
        }
    }

    private func updateCamera(with coords: [CoordinatePoint]) {
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
            span: .init(
                latitudeDelta: max(0.02, (maxLat - minLat) * 1.4),
                longitudeDelta: max(0.02, (maxLon - minLon) * 1.4)
            )
        ))
    }

    @MainActor
    private func save() async {
        errorMessage = nil
        guard endDate >= startDate else {
            errorMessage = "End must be after start."
            return
        }
        guard let distance = Double(distanceValue.replacingOccurrences(of: ",", with: ".")), distance >= 0 else {
            errorMessage = "Enter a valid distance."
            return
        }
        let meters: Double = settings.settings.distanceUnit == .miles
            ? DistanceCalculator.milesToMeters(distance)
            : DistanceCalculator.kilometersToMeters(distance)

        let from = fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = toAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        isSaving = true
        defer { isSaving = false }

        var routed: GeocodingService.RoutedJourney?
        var routeFailed = false
        if !from.isEmpty && !to.isEmpty {
            // Prefer live preview if it matches current addresses; otherwise recalculate.
            if from == lastRoutedFrom, to == lastRoutedTo, previewPoints.count >= 2, let travel = expectedTravelTime {
                let pathMeters: Double = {
                    // Recompute distance from current distance field (may be overridden).
                    return meters
                }()
                _ = pathMeters
                routed = GeocodingService.RoutedJourney(
                    points: previewPoints,
                    distanceMeters: meters,
                    expectedTravelTime: travel
                )
            } else if let journey = await GeocodingService.directionsRouteOrNil(
                from: from,
                to: to,
                startDate: startDate
            ) {
                routed = journey
                previewPoints = journey.points
                expectedTravelTime = journey.expectedTravelTime
            } else {
                routeFailed = true
            }
        }

        do {
            let repo = TripRepository(context: modelContext)
            switch mode {
            case .add:
                let trip = TripEntity(
                    startDate: startDate,
                    endDate: endDate,
                    distanceMeters: meters,
                    classification: classification,
                    purpose: purpose,
                    notes: notes,
                    fromAddress: from,
                    toAddress: to,
                    isManual: true,
                    isAutoDetected: false,
                    routePoints: routed?.points ?? []
                )
                try repo.add(trip)
            case .edit(let trip):
                trip.startDate = startDate
                trip.endDate = endDate
                trip.distanceMeters = meters
                trip.classification = classification
                trip.purpose = purpose
                trip.notes = notes
                trip.fromAddress = from
                trip.toAddress = to
                // Drive map from addresses for manual trips (or trips without a GPS polyline).
                let canReplaceRoute = trip.isManual || trip.routePoints.count < 2
                if canReplaceRoute {
                    if let routed {
                        trip.routePoints = routed.points
                    } else if from.isEmpty || to.isEmpty {
                        if trip.isManual {
                            trip.routePoints = []
                        }
                    } else if routeFailed, trip.isManual {
                        trip.routePoints = []
                    }
                }
                try repo.update(trip)
            }
            if routeFailed {
                AnalyticsStub.log("trip_geocode_failed")
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            CrashProtocolStub.record(error)
        }
    }
}
