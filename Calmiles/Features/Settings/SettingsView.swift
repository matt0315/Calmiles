import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @StateObject private var tripDetection = TripDetectionService.shared

    @State private var showPaywall = false
    @State private var showDeleteConfirm = false
    @State private var exportMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Preferences") {
                    Picker("Country", selection: countryBinding) {
                        ForEach(CountryCode.allCases) { c in
                            Text("\(c.displayName) (\(c.authorityName))").tag(c)
                        }
                    }
                    Picker("Units", selection: unitBinding) {
                        ForEach(DistanceUnit.allCases) { u in
                            Text(u.displayName).tag(u)
                        }
                    }
                    Toggle("Auto-detect trips", isOn: autoDetectBinding)
                }

                Section {
                    if let preset = activePreset {
                        LabeledContent("Rate table", value: preset.name)
                        LabeledContent("Rate", value: "\(preset.ratePerUnit) / \(preset.unit.shortLabel)")
                        Text(preset.notes)
                            .font(CalmilesTypography.caption)
                            .foregroundStyle(Color.calmilesSecondaryText)
                    }
                    Text(RatePreset.notTaxAdviceDisclaimer)
                        .font(CalmilesTypography.caption)
                        .foregroundStyle(Color.calmilesSecondaryText)
                } header: {
                    Text("Mileage rates")
                }

                Section("Subscription") {
                    if subscriptions.isPro {
                        LabeledContent("Plan", value: "Calmiles Pro")
                        Button("Manage Subscription") {
                            Task { await subscriptions.manageSubscriptions() }
                        }
                    } else {
                        LabeledContent(
                            "Free auto-trips remaining",
                            value: "\(settings.settings.remainingFreeAutoTrips) / \(AppSettings.freeAutoTripLimit)"
                        )
                        Button("Upgrade to Pro") { showPaywall = true }
                        Button("Restore Purchases") {
                            Task { await subscriptions.restore() }
                        }
                    }
                }

                Section("Location") {
                    LabeledContent("Permission", value: authLabel)
                    if tripDetection.isTracking {
                        Text("Tracking active").foregroundStyle(CalmilesColor.success)
                    }
                    #if DEBUG
                    Button("Inject sample trip (DEBUG)") {
                        TripDetectionService.shared.injectSampleTrip()
                    }
                    #endif
                }

                Section("Support & legal") {
                    Link("Email support", destination: URL(string: "mailto:support@botland.studio")!)
                    Link("Privacy Policy (placeholder)", destination: URL(string: "https://botland.studio/calmiles/privacy")!)
                    Link("Terms of Use (placeholder)", destination: URL(string: "https://botland.studio/calmiles/terms")!)
                }

                Section("Data") {
                    Button("Export all data (CSV)") {
                        exportAll()
                    }
                    Button("Delete all trip data", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }

                Section {
                    LabeledContent("Version", value: "1.0.0 (1)")
                    LabeledContent("Bundle ID", value: "studio.botland.calmiles")
                }

                if let exportMessage {
                    Section { Text(exportMessage) }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .confirmationDialog("Delete all trips? This cannot be undone.", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) { deleteAll() }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear { AnalyticsStub.screen("settings") }
        }
    }

    private var countryBinding: Binding<CountryCode> {
        Binding(
            get: { settings.settings.country },
            set: {
                settings.settings.country = $0
                settings.settings.distanceUnit = $0.defaultDistanceUnit
                settings.settings.selectedRatePresetID = RateTable.activePreset(for: $0)?.id
            }
        )
    }

    private var unitBinding: Binding<DistanceUnit> {
        Binding(
            get: { settings.settings.distanceUnit },
            set: { settings.settings.distanceUnit = $0 }
        )
    }

    private var autoDetectBinding: Binding<Bool> {
        Binding(
            get: { settings.settings.autoDetectEnabled },
            set: { enabled in
                settings.settings.autoDetectEnabled = enabled
                if enabled { tripDetection.start() } else { tripDetection.stop() }
            }
        )
    }

    private var activePreset: RatePreset? {
        if let id = settings.settings.selectedRatePresetID {
            return RateTable.presets.first { $0.id == id } ?? RateTable.activePreset(for: settings.settings.country)
        }
        return RateTable.activePreset(for: settings.settings.country)
    }

    private var authLabel: String {
        switch tripDetection.authorizationStatus {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "When In Use"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not Determined"
        @unknown default: return "Unknown"
        }
    }

    private func exportAll() {
        do {
            let trips = try TripRepository(context: modelContext).fetchAll()
            let service = ExportService(unit: settings.settings.distanceUnit, country: settings.settings.country, includeEstimates: true)
            let csv = service.csv(from: trips)
            UIPasteboard.general.string = csv
            exportMessage = "CSV copied to clipboard (\(trips.count) trips)."
        } catch {
            exportMessage = error.localizedDescription
            CrashProtocolStub.record(error)
        }
    }

    private func deleteAll() {
        do {
            try TripRepository(context: modelContext).deleteAll()
            exportMessage = "All trip data deleted."
            AnalyticsStub.log("data_deleted")
        } catch {
            exportMessage = error.localizedDescription
            CrashProtocolStub.record(error)
        }
    }
}
