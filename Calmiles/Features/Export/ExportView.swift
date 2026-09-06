import SwiftUI
import SwiftData

struct ExportView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: SettingsStore
    @Query(sort: \TripEntity.startDate, order: .reverse) private var trips: [TripEntity]

    @State private var dateFrom = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var dateTo = Date()
    @State private var businessOnly = false
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Range") {
                    DatePicker("From", selection: $dateFrom, displayedComponents: .date)
                    DatePicker("To", selection: $dateTo, displayedComponents: .date)
                    Toggle("Business only", isOn: $businessOnly)
                }
                Section {
                    Text("Exports include distance, classification, purpose, and labeled estimates. Not tax advice.")
                        .font(CalmilesTypography.caption)
                        .foregroundStyle(Color.calmilesSecondaryText)
                }
                Section {
                    Button {
                        Task { await exportCSV() }
                    } label: {
                        Label("Export CSV", systemImage: "tablecells")
                    }
                    .disabled(isWorking)
                    Button {
                        Task { await exportPDF() }
                    } label: {
                        Label("Export PDF", systemImage: "doc.richtext")
                    }
                    .disabled(isWorking)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(CalmilesColor.danger)
                    }
                }
            }
            .navigationTitle("Export")
            .overlay {
                if isWorking { LoadingStateView(message: "Preparing export…") }
            }
            .sheet(isPresented: $showShare) {
                if let shareURL {
                    ActivityView(activityItems: [shareURL])
                }
            }
            .onAppear { AnalyticsStub.screen("export") }
        }
    }

    private var filteredTrips: [TripEntity] {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: dateTo)) ?? dateTo
        return trips.filter { trip in
            trip.startDate >= dateFrom && trip.startDate < end &&
            (!businessOnly || trip.classification == .business)
        }
    }

    private func exportCSV() async {
        await runExport(ext: "csv") { service, trips in
            let csv = service.csv(from: trips)
            return csv.data(using: .utf8) ?? Data()
        }
    }

    private func exportPDF() async {
        await runExport(ext: "pdf") { service, trips in
            service.pdfData(from: trips)
        }
    }

    private func runExport(ext: String, builder: (ExportService, [TripEntity]) -> Data) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        let selected = filteredTrips
        guard !selected.isEmpty else {
            errorMessage = "No trips in this range."
            return
        }
        let service = ExportService(
            unit: settings.settings.distanceUnit,
            country: settings.settings.country,
            includeEstimates: true
        )
        let data = builder(service, selected)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Calmiles-Export-\(Int(Date().timeIntervalSince1970)).\(ext)")
        do {
            try data.write(to: url, options: .atomic)
            shareURL = url
            showShare = true
            AnalyticsStub.log("export_\(ext)")
        } catch {
            errorMessage = error.localizedDescription
            CrashProtocolStub.record(error)
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
