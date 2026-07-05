import Foundation

/// Service for searching and retrieving book data from Google Books API
actor GoogleBooksService {
    private let config = APIConfiguration.shared
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Search by ISBN

    func searchByISBN(_ isbn: String) async throws -> [BookSearchResult] {
        let query = "isbn:\(isbn)"
        return try await search(query: query)
    }

    // MARK: - Search by Title and/or Author

    func search(title: String? = nil, author: String? = nil, publisher: String? = nil) async throws -> [BookSearchResult] {
        var parts: [String] = []
        if let title = title, !title.isEmpty {
            parts.append("intitle:\(title)")
        }
        if let author = author, !author.isEmpty {
            parts.append("inauthor:\(author)")
        }
        if let publisher = publisher, !publisher.isEmpty {
            parts.append("inpublisher:\(publisher)")
        }
        guard !parts.isEmpty else { return [] }
        let query = parts.joined(separator: "+")
        return try await search(query: query)
    }

    // MARK: - General Search

    func search(query: String, maxResults: Int = 10) async throws -> [BookSearchResult] {
        var components = URLComponents(string: config.googleBooksBaseURL)!
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]

        if !config.googleBooksAPIKey.isEmpty {
            queryItems.append(URLQueryItem(name: "key", value: config.googleBooksAPIKey))
        }

        components.queryItems = queryItems

        // URLComponents percent-encodes colons in query values, but Google Books
        // expects them unencoded (e.g. "isbn:123" not "isbn%3A123").
        // Build the URL string manually from the components, then unencode colons.
        guard var urlString = components.url?.absoluteString else {
            throw BookServiceError.invalidURL
        }
        urlString = urlString.replacingOccurrences(of: "isbn%3A", with: "isbn:")
        urlString = urlString.replacingOccurrences(of: "intitle%3A", with: "intitle:")
        urlString = urlString.replacingOccurrences(of: "inauthor%3A", with: "inauthor:")
        urlString = urlString.replacingOccurrences(of: "inpublisher%3A", with: "inpublisher:")

        guard let url = URL(string: urlString) else {
            throw BookServiceError.invalidURL
        }

        print("[GoogleBooks] Requesting: \(url.absoluteString)")

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BookServiceError.networkError
        }

        print("[GoogleBooks] Status: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            print("[GoogleBooks] Error body: \(body)")
            if httpResponse.statusCode == 429 {
                throw BookServiceError.rateLimited
            }
            throw BookServiceError.networkError
        }

        let decoded = try JSONDecoder().decode(GoogleBooksResponse.self, from: data)

        guard let items = decoded.items else { return [] }

        return items.compactMap { item -> BookSearchResult? in
            guard let info = item.volumeInfo, let title = info.title else { return nil }

            let isbn10 = info.industryIdentifiers?.first(where: { $0.type == "ISBN_10" })?.identifier
            let isbn13 = info.industryIdentifiers?.first(where: { $0.type == "ISBN_13" })?.identifier

            return BookSearchResult(
                title: title,
                authors: info.authors?.joined(separator: ", ") ?? "Unknown Author",
                isbn: isbn10,
                isbn13: isbn13,
                publisher: info.publisher,
                publishedDate: info.publishedDate,
                description: info.description,
                pageCount: info.pageCount,
                categories: info.categories?.joined(separator: ", "),
                language: info.language,
                coverImageURL: info.imageLinks?.bestURL,
                source: .googleBooks
            )
        }
    }
}

// MARK: - Download Cover Image

extension GoogleBooksService {
    func downloadCoverImage(from urlString: String) async throws -> Data {
        // Google Books sometimes returns small thumbnails; request a larger size
        let largerURL = urlString
            .replacingOccurrences(of: "zoom=1", with: "zoom=2")
            .replacingOccurrences(of: "&edge=curl", with: "")

        guard let url = URL(string: largerURL) else {
            throw BookServiceError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw BookServiceError.networkError
        }

        return data
    }
}

// MARK: - Errors

enum BookServiceError: LocalizedError {
    case invalidURL
    case networkError
    case decodingError
    case notFound
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .networkError: return "Network request failed"
        case .decodingError: return "Failed to parse response"
        case .notFound: return "No results found"
        case .rateLimited: return "Too many requests — please try again shortly"
        }
    }
}
