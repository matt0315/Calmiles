import SwiftUI
import SwiftData
import MapKit

enum TripEditMode {
    case add
    case edit(TripEntity)
}

private enum AddressField: Hashable {
    case from
    case to
}

struct TripEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: SettingsStore

    let mode: TripEditMode

    @StateObject private var addressSearch = AddressSearchCompleter()
    @FocusState private var focusedAddress: AddressField?

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
    @State private var fromPlace: GeocodingService.ResolvedPlace?
    @State private var toPlace: GeocodingService.ResolvedPlace?
    @State private var applyingAddress = false
    @State private var isLoadingForm = true
    @State private var calculatedDistanceMeters: Double?
    @State private var routeGeneration = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Route") {
                    addressField(title: "From", text: $fromAddress, field: .from, place: fromPlace)
                    if focusedAddress == .from {
                        suggestionList
                    }
                    addressField(title: "To", text: $toAddress, field: .to, place: toPlace)
                    if focusedAddress == .to {
                        suggestionList
                    }
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
                            // Only lock distance after a route has been applied or the user edits
                            // a calculated value. The initial "10" is a placeholder, not an override.
                            if expectedTravelTime != nil || !previewPoints.isEmpty || calculatedDistanceMeters != nil {
                                distanceOverridden = true
                            } else if distanceValue.trimmingCharacters(in: .whitespaces) != "10" {
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
            .onChange(of: fromAddress) { _, _ in
                handleAddressTextChanged(.from)
            }
            .onChange(of: toAddress) { _, _ in
                handleAddressTextChanged(.to)
            }
            .onChange(of: focusedAddress) { _, field in
                addressSearch.setHint(searchHint)
                if let field {
                    addressSearch.updateQuery(text(for: field))
                } else {
                    addressSearch.clear()
                }
            }
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
        return from.count >= 3 && to.count >= 3
    }

    private var searchHint: CLLocationCoordinate2D? {
        TripDetectionService.shared.lastKnownCoordinate
    }

    @ViewBuilder
    private func addressField(
        title: String,
        text: Binding<String>,
        field: AddressField,
        place: GeocodingService.ResolvedPlace?
    ) -> some View {
        TextField(title, text: text)
            .textContentType(.fullStreetAddress)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .focused($focusedAddress, equals: field)
            .submitLabel(.next)
            .onSubmit { scheduleRouteCalculation(immediate: true) }
            .accessibilityLabel(title)
            .accessibilityHint(place == nil ? "Type an address. Suggestions appear as you type." : "Address selected")
    }

    @ViewBuilder
    private var suggestionList: some View {
        if addressSearch.suggestions.isEmpty {
            EmptyView()
        } else {
            ForEach(Array(addressSearch.suggestions.enumerated()), id: \.offset) { _, completion in
                Button {
                    Task { await select(completion) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(completion.title)
                            .font(CalmilesTypography.body)
                            .foregroundStyle(Color.calmilesPrimaryText)
                        if !completion.subtitle.isEmpty {
                            Text(completion.subtitle)
                                .font(CalmilesTypography.caption)
                                .foregroundStyle(Color.calmilesSecondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(completion.title), \(completion.subtitle)")
            }
        }
    }

    private func text(for field: AddressField) -> String {
        switch field {
        case .from: return fromAddress
        case .to: return toAddress
        }
    }

    private func load() {
        isLoadingForm = true
        addressSearch.setHint(searchHint)
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
            // Don't preview a stored 2-point chord — that's the old geodesic, not a road.
            if trip.routePoints.count >= 3 {
                previewPoints = trip.routePoints
                updateCamera(with: previewPoints)
            } else {
                previewPoints = []
            }
            // Existing distance/end are treated as authoritative until addresses change.
            distanceOverridden = true
            endOverridden = true
            lastRoutedFrom = fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            lastRoutedTo = toAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            let travel = trip.endDate.timeIntervalSince(trip.startDate)
            if travel > 0 {
                expectedTravelTime = travel
            }
            calculatedDistanceMeters = trip.distanceMeters
        }
        isLoadingForm = false
        if canAttemptRoute {
            scheduleRouteCalculation(immediate: true)
        }
    }

    private func handleAddressTextChanged(_ field: AddressField) {
        guard !isLoadingForm, !applyingAddress else { return }
        switch field {
        case .from:
            if !placeMatches(fromPlace, query: fromAddress) { fromPlace = nil }
        case .to:
            if !placeMatches(toPlace, query: toAddress) { toPlace = nil }
        }
        if focusedAddress == field {
            addressSearch.setHint(searchHint)
            addressSearch.updateQuery(text(for: field))
        }
        let from = fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = toAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if from != lastRoutedFrom || to != lastRoutedTo {
            // A new pair should receive the calculated km / ETA, not the 10 km / 1h placeholders.
            if !from.isEmpty, !to.isEmpty {
                distanceOverridden = false
                endOverridden = false
            }
        }
        scheduleRouteCalculation(immediate: false)
    }

    private func placeMatches(_ place: GeocodingService.ResolvedPlace?, query: String) -> Bool {
        guard let place else { return false }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q == place.display || fromOrToContains(place.display, query: q)
    }

    private func fromOrToContains(_ display: String, query: String) -> Bool {
        let q = query.lowercased()
        let d = display.lowercased()
        return !q.isEmpty && (d == q || d.hasPrefix(q) || q.hasPrefix(d))
    }

    private func select(_ completion: MKLocalSearchCompletion) async {
        let field = focusedAddress ?? .from
        let display = GeocodingService.displayString(title: completion.title, subtitle: completion.subtitle)
        applyingAddress = true
        switch field {
        case .from:
            fromAddress = display
            fromPlace = nil
        case .to:
            toAddress = display
            toPlace = nil
        }
        addressSearch.clear()
        applyingAddress = false

        do {
            let place = try await GeocodingService.resolve(completion: completion, near: searchHint ?? GeocodingService.perthCenter)
            applyingAddress = true
            switch field {
            case .from:
                fromPlace = place
                if fromAddress != place.display {
                    fromAddress = place.display
                }
            case .to:
                toPlace = place
                if toAddress != place.display {
                    toAddress = place.display
                }
            }
            applyingAddress = false
            focusedAddress = field == .from ? .to : nil
            scheduleRouteCalculation(immediate: true)
        } catch {
            applyingAddress = false
            routeStatusMessage = "Couldn’t look up that address. Try another suggestion."
        }
    }

    private func scheduleRouteCalculation(immediate: Bool) {
        routeTask?.cancel()
        routeGeneration += 1
        let generation = routeGeneration
        let from = fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = toAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard from.count >= 3, to.count >= 3 else {
            isRouting = false
            if from.isEmpty || to.isEmpty {
                routeStatusMessage = nil
                previewPoints = []
                expectedTravelTime = nil
                calculatedDistanceMeters = nil
                lastRoutedFrom = ""
                lastRoutedTo = ""
            }
            return
        }
        // Skip if addresses unchanged and we already have a real road route.
        if from == lastRoutedFrom, to == lastRoutedTo, previewPoints.count >= 3, !immediate {
            return
        }
        routeTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(nanoseconds: 700_000_000)
                if Task.isCancelled { return }
            }
            await calculateRoute(generation: generation)
        }
    }

    @MainActor
    private func calculateRoute() async {
        routeGeneration += 1
        await calculateRoute(generation: routeGeneration)
    }

    @MainActor
    private func calculateRoute(generation: Int) async {
        let from = fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = toAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard from.count >= 3, to.count >= 3 else { return }
        guard generation == routeGeneration else { return }

        isRouting = true
        routeStatusMessage = nil
        defer { if generation == routeGeneration { isRouting = false } }

        do {
            let journey = try await GeocodingService.directionsRoute(
                from: from,
                to: to,
                startDate: startDate,
                fromPlace: matchingPlace(fromPlace, query: from),
                toPlace: matchingPlace(toPlace, query: to),
                near: searchHint
            )
            if Task.isCancelled || generation != routeGeneration { return }
            apply(journey, from: from, to: to)
        } catch {
            if Task.isCancelled || generation != routeGeneration { return }
            previewPoints = []
            expectedTravelTime = nil
            calculatedDistanceMeters = nil
            lastRoutedFrom = ""
            lastRoutedTo = ""
            routeStatusMessage = "Couldn’t calculate a driving route for these addresses."
        }
    }

    private func matchingPlace(_ place: GeocodingService.ResolvedPlace?, query: String) -> GeocodingService.ResolvedPlace? {
        guard let place, fromOrToContains(place.display, query: query) || query == place.display else { return nil }
        return place
    }

    private func apply(_ journey: GeocodingService.RoutedJourney, from: String, to: String) {
        previewPoints = journey.points
        expectedTravelTime = journey.expectedTravelTime
        calculatedDistanceMeters = journey.distanceMeters
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
        focusedAddress = nil
        addressSearch.clear()

        let from = fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = toAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        // Wait out a debounced calc, then make sure distance/end come from the road route.
        if !from.isEmpty, !to.isEmpty {
            routeTask?.cancel()
            await calculateRoute()
        }

        guard endDate >= startDate else {
            errorMessage = "End must be after start."
            return
        }

        let journeyMeters = calculatedDistanceMeters
        let shouldUseRouteDistance = !distanceOverridden && journeyMeters != nil
        let parsed = Double(distanceValue.replacingOccurrences(of: ",", with: "."))
        let displayDistance: Double
        if shouldUseRouteDistance, let journeyMeters {
            displayDistance = DistanceCalculator.convert(meters: journeyMeters, to: settings.settings.distanceUnit)
            distanceValue = String(format: "%.2f", displayDistance)
        } else if let parsed, parsed >= 0 {
            displayDistance = parsed
        } else {
            errorMessage = "Enter a valid distance."
            return
        }

        let meters: Double
        if shouldUseRouteDistance, let journeyMeters {
            meters = journeyMeters
        } else {
            meters = settings.settings.distanceUnit == .miles
                ? DistanceCalculator.milesToMeters(displayDistance)
                : DistanceCalculator.kilometersToMeters(displayDistance)
        }

        if !endOverridden, let travel = expectedTravelTime {
            endDate = startDate.addingTimeInterval(travel)
        }

        isSaving = true
        defer { isSaving = false }

        var routed: GeocodingService.RoutedJourney?
        var routeFailed = false
        if !from.isEmpty && !to.isEmpty {
            if from == lastRoutedFrom, to == lastRoutedTo, previewPoints.count >= 3, let travel = expectedTravelTime {
                routed = GeocodingService.RoutedJourney(
                    points: previewPoints,
                    distanceMeters: journeyMeters ?? meters,
                    expectedTravelTime: travel
                )
            } else if let journey = await GeocodingService.directionsRouteOrNil(
                from: from,
                to: to,
                startDate: startDate,
                fromPlace: matchingPlace(fromPlace, query: from),
                toPlace: matchingPlace(toPlace, query: to),
                near: searchHint
            ) {
                apply(journey, from: from, to: to)
                routed = journey
            } else {
                routeFailed = true
            }
        }

        let savedMeters: Double
        if !distanceOverridden, let routed {
            savedMeters = routed.distanceMeters
        } else {
            savedMeters = meters
        }

        do {
            let repo = TripRepository(context: modelContext)
            switch mode {
            case .add:
                let trip = TripEntity(
                    startDate: startDate,
                    endDate: endDate,
                    distanceMeters: savedMeters,
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
                trip.distanceMeters = savedMeters
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
                        // Drop the old straight-line chord; don't keep a fake ocean line.
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
