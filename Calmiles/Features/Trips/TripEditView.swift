import SwiftUI
import SwiftData

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

    var body: some View {
        NavigationStack {
            Form {
                Section("Route") {
                    TextField("From", text: $fromAddress)
                        .textContentType(.fullStreetAddress)
                        .autocorrectionDisabled()
                    TextField("To", text: $toAddress)
                        .textContentType(.fullStreetAddress)
                        .autocorrectionDisabled()
                }
                Section("When") {
                    DatePicker("Start", selection: $startDate)
                    DatePicker("End", selection: $endDate)
                }
                Section("Distance (\(settings.settings.distanceUnit.shortLabel))") {
                    TextField("Distance", text: $distanceValue)
                        .keyboardType(.decimalPad)
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
        }
    }

    private var title: String {
        switch mode {
        case .add: return "Add Trip"
        case .edit: return "Edit Trip"
        }
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
        }
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

        var geocodedRoute: [CoordinatePoint]?
        var geocodeFailed = false
        if !from.isEmpty && !to.isEmpty {
            if let points = await GeocodingService.routeEndpoints(
                from: from,
                to: to,
                startDate: startDate,
                endDate: endDate
            ) {
                geocodedRoute = points
            } else {
                geocodeFailed = true
            }
        }

        do {
            let repo = TripRepository(context: modelContext)
            switch mode {
            case .add:
                var routePoints: [CoordinatePoint] = []
                if let geocodedRoute {
                    routePoints = geocodedRoute
                }
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
                    routePoints: routePoints
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
                    if let geocodedRoute {
                        trip.routePoints = geocodedRoute
                    } else if from.isEmpty || to.isEmpty {
                        // Cleared addresses on a manual trip — drop synthetic route.
                        if trip.isManual {
                            trip.routePoints = []
                        }
                    } else if geocodeFailed, trip.isManual {
                        // Keep addresses; clear stale synthetic map so detail shows empty state.
                        trip.routePoints = []
                    }
                }
                try repo.update(trip)
            }
            if geocodeFailed {
                // Addresses saved; map will show graceful empty state.
                AnalyticsStub.log("trip_geocode_failed")
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            CrashProtocolStub.record(error)
        }
    }
}
