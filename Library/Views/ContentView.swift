import SwiftUI

/// Root tab view for the app
struct ContentView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }

            PriceCheckView()
                .tabItem {
                    Label("Price Check", systemImage: "barcode.viewfinder")
                }

            PriceSummaryView()
                .tabItem {
                    Label("Prices", systemImage: "tag")
                }

            WatchlistView()
                .tabItem {
                    Label("Watchlist", systemImage: "eye")
                }

            ReadingStatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}
