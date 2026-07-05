import Foundation
import SwiftData

/// A single price observation for a WatchedBook, recorded each time prices are refreshed.
@Model
final class WatchedPriceEntry {
    var price: Double
    var currency: String
    var fetchedAt: Date
    var watchedBook: WatchedBook?

    init(price: Double, currency: String = "USD") {
        self.price = price
        self.currency = currency
        self.fetchedAt = Date()
    }
}
