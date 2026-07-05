import Foundation
import os

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
            return (false, "Enter a Client ID + Secret, or a direct App Token")
        }

        // Clear cached token so we force a fresh auth attempt
        cachedToken = nil
        tokenExpiry = nil

        do {
            let token = try await getAccessToken()
            if token.isEmpty {
                return (false, "Received empty token")
            }
            if !config.ebayAppToken.isEmpty && !hasClientCredentials {
                return (true, "Using your App Token directly")
            }
            return (true, "Authenticated successfully")
        } catch EbayError.authenticationFailed {
            return (false, "Authentication failed — double-check your Client ID and Secret")
        } catch {
            return (false, "Connection error: \(error.localizedDescription)")
        }
    }

    private var hasClientCredentials: Bool {
        !config.ebayClientID.isEmpty && !config.ebayClientSecret.isEmpty
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

            Logger.ebay.debug("Fetching details for item \(itemID)")
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                Logger.ebay.error("Item lookup failed with status \(status)")
                return nil
            }

            let detail = try JSONDecoder().decode(EbayItemDetailResponse.self, from: data)
            return detail.title

        } catch {
            Logger.ebay.error("Item lookup error: \(error)")
            return nil
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

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            Logger.ebay.error("Auth failed (\(httpResponse.statusCode)): \(body)")
            throw EbayError.authenticationFailed
        }

        let tokenResponse = try JSONDecoder().decode(EbayTokenResponse.self, from: data)
        Logger.ebay.debug("Token acquired, expires in \(tokenResponse.expiresIn)s")

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

        Logger.ebay.debug("Searching: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("EBAY_US", forHTTPHeaderField: "X-EBAY-C-MARKETPLACE-ID")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EbayError.networkError
        }

        if httpResponse.statusCode == 429 {
            throw EbayError.rateLimited
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            Logger.ebay.error("Search failed (\(httpResponse.statusCode)): \(body)")
            throw EbayError.networkError
        }

        let decoded = try JSONDecoder().decode(EbaySearchResponse.self, from: data)

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

nonisolated struct EbayPriceResult {
    let lowestPrice: Double
    let currency: String
    let title: String
    let condition: String?
    let listingURL: String?
    let imageURL: String?
    let searchResultsURL: String?

    var formattedPrice: String {
        lowestPrice.formattedAsPrice(currency: currency)
    }
}

nonisolated struct EbayTokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

private nonisolated struct EbayItemDetailResponse: Decodable {
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
