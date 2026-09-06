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
    @State private var distanceValue: String = "10"
    @State private var classification: TripClassification = .undecided
    @State private var purpose: String = ""
    @State private var notes: String = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
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
            let v = DistanceCalculator.convert(meters: trip.distanceMeters, to: settings.settings.distanceUnit)
            distanceValue = String(format: "%.2f", v)
            classification = trip.classification
            purpose = trip.purpose
            notes = trip.notes
        }
    }

    private func save() {
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
                    isManual: true,
                    isAutoDetected: false
                )
                try repo.add(trip)
            case .edit(let trip):
                trip.startDate = startDate
                trip.endDate = endDate
                trip.distanceMeters = meters
                trip.classification = classification
                trip.purpose = purpose
                trip.notes = notes
                try repo.update(trip)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            CrashProtocolStub.record(error)
        }
    }
}
