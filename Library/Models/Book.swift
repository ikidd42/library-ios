import Foundation
import SwiftData

@Model
final class Book {
    // MARK: - Core Info
    var title: String
    var authors: String          // comma-separated for simplicity
    var isbn: String?
    var isbn13: String?
    var publisher: String?
    var publishedDate: String?
    var bookDescription: String?
    var pageCount: Int?
    var categories: String?      // comma-separated
    var language: String?

    // MARK: - Cover Image
    var coverImageURL: String?
    @Attribute(.externalStorage) var coverImageData: Data?

    // MARK: - Library Metadata
    var readingStatus: String     // ReadingStatus raw value
    var dateAdded: Date
    var dateStartedReading: Date?
    var dateFinishedReading: Date?
    var personalNotes: String?
    var rating: Int?              // 1-5 stars

    // MARK: - Copies
    var copyCount: Int = 1

    // MARK: - eBay Pricing
    var ebayLowestPrice: Double?
    var ebayPriceURL: String?
    var ebayPriceLastUpdated: Date?

    // MARK: - Price History
    @Relationship(deleteRule: .cascade, inverse: \PriceHistoryEntry.book)
    var priceHistory: [PriceHistoryEntry] = []

    // MARK: - Computed
    var readingStatusEnum: ReadingStatus {
        get { ReadingStatus(rawValue: readingStatus) ?? .wantToRead }
        set { readingStatus = newValue.rawValue }
    }

    var displayISBN: String {
        isbn13 ?? isbn ?? "No ISBN"
    }

    var authorList: [String] {
        authors.components(separatedBy: ", ")
    }

    init(
        title: String,
        authors: String,
        isbn: String? = nil,
        isbn13: String? = nil,
        publisher: String? = nil,
        publishedDate: String? = nil,
        bookDescription: String? = nil,
        pageCount: Int? = nil,
        categories: String? = nil,
        language: String? = nil,
        coverImageURL: String? = nil,
        coverImageData: Data? = nil,
        readingStatus: ReadingStatus = .wantToRead,
        personalNotes: String? = nil,
        rating: Int? = nil
    ) {
        self.title = title
        self.authors = authors
        self.isbn = isbn
        self.isbn13 = isbn13
        self.publisher = publisher
        self.publishedDate = publishedDate
        self.bookDescription = bookDescription
        self.pageCount = pageCount
        self.categories = categories
        self.language = language
        self.coverImageURL = coverImageURL
        self.coverImageData = coverImageData
        self.readingStatus = readingStatus.rawValue
        self.dateAdded = Date()
        self.personalNotes = personalNotes
        self.rating = rating
    }
}
