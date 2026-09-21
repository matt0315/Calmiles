import SwiftUI
import SwiftData

struct TripsListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: SettingsStore
    @Query(sort: \TripEntity.startDate, order: .reverse) private var trips: [TripEntity]
    @State private var showAdd = false
    @State private var filter: TripClassification? = nil

    private var filtered: [TripEntity] {
        guard let filter else { return trips }
        return trips.filter { $0.classification == filter }
    }

    var body: some View {
        NavigationStack {
            Group {
                if trips.isEmpty {
                    EmptyStateView(
                        title: "No trips",
                        message: "Auto-detected and manual trips will appear here.",
                        systemImage: "list.bullet.rectangle",
                        actionTitle: "Add Trip",
                        action: { showAdd = true }
                    )
                } else {
                    List {
                        Section {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    filterChip(nil, title: "All")
                                    ForEach(TripClassification.allCases) { c in
                                        filterChip(c, title: c.displayName)
                                    }
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                        ForEach(filtered) { trip in
                            NavigationLink {
                                TripDetailView(trip: trip)
                            } label: {
                                TripRowView(trip: trip, unit: settings.settings.distanceUnit)
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    delete(trip)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.calmilesBackground.ignoresSafeArea())
            .navigationTitle("Trips")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add trip")
                }
            }
            .sheet(isPresented: $showAdd) {
                TripEditView(mode: .add)
            }
            .onAppear { AnalyticsStub.screen("trips_list") }
        }
    }

    private func filterChip(_ value: TripClassification?, title: String) -> some View {
        let selected = filter == value
        return Button {
            filter = value
        } label: {
            Text(title)
                .font(CalmilesTypography.callout.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? CalmilesColor.copper.opacity(0.25) : Color.calmilesCard)
                .foregroundStyle(selected ? CalmilesColor.copper : Color.calmilesPrimaryText)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private func delete(_ trip: TripEntity) {
        do {
            try TripRepository(context: modelContext).delete(trip)
        } catch {
            CrashProtocolStub.record(error)
        }
    }
}
