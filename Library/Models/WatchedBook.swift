import Foundation
import SwiftData

/// A book being tracked for price changes, separate from the main library.
/// Typically added by sharing an eBay listing, or via manual search.
@Model
final class WatchedBook {
    var title: String
    var authors: String
    var isbn: String?
    var isbn13: String?

    /// Remote cover URL (e.g. from Google Books)
    var coverImageURL: String?
    /// Locally cached cover data
    @Attribute(.externalStorage) var coverImageData: Data?

    /// The specific eBay item ID that was shared (may be nil if added manually)
    var ebayItemID: String?
    /// Direct link to the specific eBay listing that was shared
    var ebayListingURL: String?
    /// Link to current search results for this book on eBay
    var ebaySearchURL: String?

    /// Current lowest market price, updated on each refresh
    var ebayLowestPrice: Double?
    var ebayPriceLastUpdated: Date?

    var dateAdded: Date
    var notes: String?

    @Relationship(deleteRule: .cascade, inverse: \WatchedPriceEntry.watchedBook)
    var priceHistory: [WatchedPriceEntry] = []

    init(
        title: String,
        authors: String = "",
        isbn: String? = nil,
        isbn13: String? = nil,
        coverImageURL: String? = nil,
        ebayItemID: String? = nil,
        ebayListingURL: String? = nil
    ) {
        self.title = title
        self.authors = authors
        self.isbn = isbn
        self.isbn13 = isbn13
        self.coverImageURL = coverImageURL
        self.ebayItemID = ebayItemID
        self.ebayListingURL = ebayListingURL
        self.dateAdded = Date()
    }

    var authorList: [String] {
        authors.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    var displayISBN: String {
        isbn13 ?? isbn ?? "No ISBN"
    }
}
