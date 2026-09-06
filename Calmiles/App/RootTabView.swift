import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            TripsListView()
                .tabItem { Label("Trips", systemImage: "list.bullet.rectangle") }
            ExportView()
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(CalmilesColor.copper)
    }
}
