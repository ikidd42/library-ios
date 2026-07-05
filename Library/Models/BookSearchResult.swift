import Foundation

/// Lightweight struct for search results before adding to library
struct BookSearchResult: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let authors: String
    let isbn: String?
    let isbn13: String?
    let publisher: String?
    let publishedDate: String?
    let description: String?
    let pageCount: Int?
    let categories: String?
    let language: String?
    let coverImageURL: String?
    let source: SearchSource

    enum SearchSource: String {
        case googleBooks = "Google Books"
        case openLibrary = "Open Library"
        case manual = "Manual Entry"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: BookSearchResult, rhs: BookSearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Google Books API Response Models

struct GoogleBooksResponse: Codable {
    let totalItems: Int?
    let items: [GoogleBookItem]?
}

struct GoogleBookItem: Codable {
    let id: String?
    let volumeInfo: GoogleVolumeInfo?
}

struct GoogleVolumeInfo: Codable {
    let title: String?
    let authors: [String]?
    let publisher: String?
    let publishedDate: String?
    let description: String?
    let industryIdentifiers: [GoogleIndustryIdentifier]?
    let pageCount: Int?
    let categories: [String]?
    let imageLinks: GoogleImageLinks?
    let language: String?
}

struct GoogleIndustryIdentifier: Codable {
    let type: String?
    let identifier: String?
}

struct GoogleImageLinks: Codable {
    let smallThumbnail: String?
    let thumbnail: String?

    /// Returns the best available image URL, upgrading to HTTPS
    var bestURL: String? {
        let url = thumbnail ?? smallThumbnail
        return url?.replacingOccurrences(of: "http://", with: "https://")
    }
}

// MARK: - Open Library API Response Models

struct OpenLibrarySearchResponse: Codable {
    let docs: [OpenLibraryDoc]?
}

struct OpenLibraryDoc: Codable {
    let title: String?
    let authorName: [String]?
    let isbn: [String]?
    let publisher: [String]?
    let firstPublishYear: Int?
    let numberOfPagesMedian: Int?
    let subject: [String]?
    let coverI: Int?
    let language: [String]?

    enum CodingKeys: String, CodingKey {
        case title
        case authorName = "author_name"
        case isbn
        case publisher
        case firstPublishYear = "first_publish_year"
        case numberOfPagesMedian = "number_of_pages_median"
        case subject
        case coverI = "cover_i"
        case language
    }
}

// MARK: - eBay API Response Models

struct EbaySearchResponse: Codable {
    let itemSummaries: [EbayItemSummary]?
}

struct EbayItemSummary: Codable {
    let title: String?
    let price: EbayPrice?
    let itemWebUrl: String?
    let condition: String?
    let image: EbayImage?
}

struct EbayPrice: Codable {
    let value: String?
    let currency: String?

    var doubleValue: Double? {
        guard let value = value else { return nil }
        return Double(value)
    }
}

struct EbayImage: Codable {
    let imageUrl: String?
}
