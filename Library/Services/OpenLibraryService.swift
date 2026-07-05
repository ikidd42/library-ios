import Foundation

/// Fallback service using the Open Library API (no key required)
actor OpenLibraryService {
    private let config = APIConfiguration.shared
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Search by ISBN

    func searchByISBN(_ isbn: String) async throws -> [BookSearchResult] {
        let urlString = "\(config.openLibraryBaseURL)/search.json?isbn=\(isbn)&limit=5"

        guard let url = URL(string: urlString) else {
            throw BookServiceError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw BookServiceError.networkError
        }

        let decoded = try JSONDecoder().decode(OpenLibrarySearchResponse.self, from: data)
        return mapResults(decoded.docs ?? [])
    }

    // MARK: - Search by Title/Author

    func search(title: String? = nil, author: String? = nil) async throws -> [BookSearchResult] {
        var queryParts: [String] = []
        if let title = title, !title.isEmpty {
            queryParts.append("title=\(title)")
        }
        if let author = author, !author.isEmpty {
            queryParts.append("author=\(author)")
        }
        guard !queryParts.isEmpty else { return [] }

        let queryString = queryParts.joined(separator: "&")
        let urlString = "\(config.openLibraryBaseURL)/search.json?\(queryString)&limit=10"

        guard let encodedString = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encodedString) else {
            throw BookServiceError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw BookServiceError.networkError
        }

        let decoded = try JSONDecoder().decode(OpenLibrarySearchResponse.self, from: data)
        return mapResults(decoded.docs ?? [])
    }

    // MARK: - Cover Image URL

    func coverImageURL(isbn: String, size: CoverSize = .large) -> String {
        "\(config.openLibraryCoversURL)/b/isbn/\(isbn)-\(size.rawValue).jpg"
    }

    func coverImageURL(coverID: Int, size: CoverSize = .large) -> String {
        "\(config.openLibraryCoversURL)/b/id/\(coverID)-\(size.rawValue).jpg"
    }

    enum CoverSize: String {
        case small = "S"
        case medium = "M"
        case large = "L"
    }

    // MARK: - Private Helpers

    private func mapResults(_ docs: [OpenLibraryDoc]) -> [BookSearchResult] {
        docs.compactMap { doc -> BookSearchResult? in
            guard let title = doc.title else { return nil }

            let isbn13 = doc.isbn?.first(where: { $0.count == 13 })
            let isbn10 = doc.isbn?.first(where: { $0.count == 10 })
            let coverURL: String?
            if let coverID = doc.coverI {
                coverURL = "\(config.openLibraryCoversURL)/b/id/\(coverID)-L.jpg"
            } else if let isbn = isbn13 ?? isbn10 {
                coverURL = "\(config.openLibraryCoversURL)/b/isbn/\(isbn)-L.jpg"
            } else {
                coverURL = nil
            }

            return BookSearchResult(
                title: title,
                authors: doc.authorName?.joined(separator: ", ") ?? "Unknown Author",
                isbn: isbn10,
                isbn13: isbn13,
                publisher: doc.publisher?.first,
                publishedDate: doc.firstPublishYear.map { String($0) },
                description: nil, // Open Library search doesn't return descriptions
                pageCount: doc.numberOfPagesMedian,
                categories: doc.subject?.prefix(5).joined(separator: ", "),
                language: doc.language?.first,
                coverImageURL: coverURL,
                source: .openLibrary
            )
        }
    }
}
