import Foundation
import SwiftData

@Model
final class PriceHistoryEntry {
    var price: Double
    var currency: String = "USD"
    var fetchedAt: Date

    // Relationship back to book
    var book: Book?

    init(price: Double, currency: String = "USD", fetchedAt: Date = Date()) {
        self.price = price
        self.currency = currency
        self.fetchedAt = fetchedAt
    }
}
