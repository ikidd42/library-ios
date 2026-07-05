import Foundation

/// Service for fetching current lowest eBay prices for books
actor EbayPriceService {
    private let config = APIConfiguration.shared
    private let session: URLSession
    private var cachedToken: String?
    private var tokenExpiry: Date?

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Test credentials by attempting to acquire an OAuth token
    func testCredentials() async -> (success: Bool, message: String) {
        guard config.ebayIsConfigured else {
            return (false, "Client ID and Client Secret are required")
        }

        // Clear cached token so we force a fresh auth attempt
        cachedToken = nil
        tokenExpiry = nil

        do {
            let token = try await getAccessToken()
            if token.isEmpty {
                return (false, "Received empty token")
            }
            return (true, "Authenticated successfully")
        } catch EbayError.authenticationFailed {
            return (false, "Authentication failed — double-check your Client ID and Secret")
        } catch {
            return (false, "Connection error: \(error.localizedDescription)")
        }
    }

    /// Fetch the lowest current price for a book on eBay.
    /// Tries progressively broader searches until results are found.
    func fetchLowestPrice(isbn: String?, title: String, author: String) async throws -> EbayPriceResult? {
        guard config.ebayIsConfigured else {
            throw EbayError.notConfigured
        }

        let token = try await getAccessToken()

        // Strategy 1: ISBN with category filter (most precise)
        if let isbn = isbn, !isbn.isEmpty {
            if let result = try await performSearch(query: isbn, token: token, categoryID: "267", filter: nil) {
                return result
            }
            // Strategy 2: ISBN without category filter
            if let result = try await performSearch(query: isbn, token: token, categoryID: nil, filter: nil) {
                return result
            }
        }

        // Strategy 3: Title + Author with Books category
        let titleAuthor = "\(title) \(author)"
        if let result = try await performSearch(query: titleAuthor, token: token, categoryID: "267", filter: nil) {
            return result
        }

        // Strategy 4: Title + Author without category (sellers miscategorize)
        if let result = try await performSearch(query: titleAuthor, token: token, categoryID: nil, filter: nil) {
            return result
        }

        // Strategy 5: Just the title (author name might not match listing)
        if let result = try await performSearch(query: title, token: token, categoryID: nil, filter: nil) {
            return result
        }

        return nil
    }

    /// Fetches the listing title for a specific eBay item ID using the Browse API item endpoint.
    /// Used during watchlist ingestion when the share sheet doesn't provide metadata.
    func fetchItemTitle(itemID: String) async -> String? {
        guard config.ebayIsConfigured else { return nil }
        do {
            let token = try await getAccessToken()
            let baseURL = config.ebayUseSandbox
                ? "https://api.sandbox.ebay.com/buy/browse/v1"
                : config.ebayBrowseBaseURL

            // eBay item endpoint expects the legacy item ID format: v1|{itemId}|0
            let legacyID = "v1|\(itemID)|0"
            guard let encodedID = legacyID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "\(baseURL)/item/\(encodedID)") else { return nil }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("EBAY_US", forHTTPHeaderField: "X-EBAY-C-MARKETPLACE-ID")

            print("[eBay Item] Fetching details for item \(itemID)")
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                print("[eBay Item] ❌ Status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                print("[eBay Item] Body: \(String(data: data, encoding: .utf8) ?? "unreadable")")
                return nil
            }

            let detail = try JSONDecoder().decode(EbayItemDetailResponse.self, from: data)
            print("[eBay Item] ✅ Title: '\(detail.title)'")
            return detail.title

        } catch {
            print("[eBay Item] ❌ \(error)")
            return nil
        }
    }

    /// Batch fetch prices for multiple books
    func fetchPrices(for books: [(isbn: String?, title: String, author: String)]) async -> [EbayPriceResult?] {
        await withTaskGroup(of: (Int, EbayPriceResult?).self) { group in
            for (index, book) in books.enumerated() {
                group.addTask {
                    let result = try? await self.fetchLowestPrice(
                        isbn: book.isbn,
                        title: book.title,
                        author: book.author
                    )
                    return (index, result)
                }
            }

            var results = Array<EbayPriceResult?>(repeating: nil, count: books.count)
            for await (index, result) in group {
                results[index] = result
            }
            return results
        }
    }

    // MARK: - OAuth Token

    private func getAccessToken() async throws -> String {
        // Return cached token if still valid
        if let token = cachedToken, let expiry = tokenExpiry, Date() < expiry {
            return token
        }

        // If user provided a direct app token, use that
        if !config.ebayAppToken.isEmpty {
            return config.ebayAppToken
        }

        // Otherwise, generate one using client credentials
        let authURL = config.ebayUseSandbox
            ? "https://api.sandbox.ebay.com/identity/v1/oauth2/token"
            : config.ebayAuthURL

        guard let url = URL(string: authURL) else {
            throw EbayError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let credentials = "\(config.ebayClientID):\(config.ebayClientSecret)"
        let encodedCredentials = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(encodedCredentials)", forHTTPHeaderField: "Authorization")

        let body = "grant_type=client_credentials&scope=https://api.ebay.com/oauth/api_scope"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EbayError.authenticationFailed
        }

        print("[eBay Auth] Status: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            print("[eBay Auth] Error: \(body)")
            throw EbayError.authenticationFailed
        }

        let tokenResponse = try JSONDecoder().decode(EbayTokenResponse.self, from: data)
        print("[eBay Auth] Token acquired, expires in \(tokenResponse.expiresIn)s")

        cachedToken = tokenResponse.accessToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60))

        return tokenResponse.accessToken
    }

    // MARK: - Search

    private func performSearch(query: String, token: String, categoryID: String?, filter: String?) async throws -> EbayPriceResult? {
        let baseURL = config.ebayUseSandbox
            ? "https://api.sandbox.ebay.com/buy/browse/v1"
            : config.ebayBrowseBaseURL

        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw EbayError.invalidURL
        }

        var urlString = "\(baseURL)/item_summary/search?q=\(encodedQuery)&sort=price&limit=10"

        if let cat = categoryID {
            urlString += "&category_ids=\(cat)"
        }

        if let filter = filter {
            urlString += "&filter=\(filter)"
        }

        guard let url = URL(string: urlString) else {
            throw EbayError.invalidURL
        }

        print("[eBay Search] Requesting: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("EBAY_US", forHTTPHeaderField: "X-EBAY-C-MARKETPLACE-ID")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EbayError.networkError
        }

        print("[eBay Search] Status: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 429 {
            throw EbayError.rateLimited
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            print("[eBay Search] Error body: \(body)")
            throw EbayError.networkError
        }

        let decoded = try JSONDecoder().decode(EbaySearchResponse.self, from: data)

        print("[eBay Search] Found \(decoded.itemSummaries?.count ?? 0) results")

        guard let items = decoded.itemSummaries, !items.isEmpty else {
            return nil
        }

        // Find lowest price among results
        let lowestItem = items
            .filter { $0.price?.doubleValue != nil }
            .min(by: { ($0.price?.doubleValue ?? .infinity) < ($1.price?.doubleValue ?? .infinity) })

        guard let item = lowestItem, let price = item.price?.doubleValue else {
            return nil
        }

        // Build the eBay web search URL so the user can browse all listings
        let webSearchURL: String? = {
            guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
            return "https://www.ebay.com/sch/i.html?_nkw=\(encoded)"
        }()

        return EbayPriceResult(
            lowestPrice: price,
            currency: item.price?.currency ?? "USD",
            title: item.title ?? "",
            condition: item.condition,
            listingURL: item.itemWebUrl,
            imageURL: item.image?.imageUrl,
            searchResultsURL: webSearchURL
        )
    }
}

// MARK: - Models

struct EbayPriceResult {
    let lowestPrice: Double
    let currency: String
    let title: String
    let condition: String?
    let listingURL: String?
    let imageURL: String?
    let searchResultsURL: String?

    var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: lowestPrice)) ?? "$\(lowestPrice)"
    }
}

struct EbayTokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

private struct EbayItemDetailResponse: Decodable {
    let title: String
}

enum EbayError: LocalizedError {
    case notConfigured
    case invalidURL
    case authenticationFailed
    case networkError
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "eBay API not configured — add your credentials in Settings"
        case .invalidURL:
            return "Invalid eBay URL"
        case .authenticationFailed:
            return "eBay authentication failed — check your API credentials"
        case .networkError:
            return "eBay request failed"
        case .rateLimited:
            return "eBay rate limit reached — try again later"
        }
    }
}
