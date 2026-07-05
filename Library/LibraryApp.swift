import SwiftUI
import SwiftData

@main
struct LibraryApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Book.self, PriceHistoryEntry.self, WatchedBook.self, WatchedPriceEntry.self])
    }
}
