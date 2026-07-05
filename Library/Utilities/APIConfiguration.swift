import Foundation
import Observation
import SwiftUI

/// Central configuration for API keys and endpoints.
/// Keys are stored in UserDefaults for easy user configuration.
/// `nonisolated` because all state lives in UserDefaults (thread-safe),
/// and the network service actors read this configuration off the main actor.
@Observable
nonisolated final class APIConfiguration {
    static let shared = APIConfiguration()

    // MARK: - Google Books
    /// Optional API key — Google Books works without one, but rate limits are higher with a key
    var googleBooksAPIKey: String {
        get { UserDefaults.standard.string(forKey: "googleBooksAPIKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "googleBooksAPIKey") }
    }

    var googleBooksBaseURL: String { "https://www.googleapis.com/books/v1/volumes" }

    // MARK: - eBay
    /// eBay OAuth App Token (client credentials grant)
    var ebayAppToken: String {
        get { UserDefaults.standard.string(forKey: "ebayAppToken") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "ebayAppToken") }
    }

    /// eBay Client ID (App ID) for OAuth token generation
    var ebayClientID: String {
        get { UserDefaults.standard.string(forKey: "ebayClientID") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "ebayClientID") }
    }

    /// eBay Client Secret for OAuth token generation
    var ebayClientSecret: String {
        get { UserDefaults.standard.string(forKey: "ebayClientSecret") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "ebayClientSecret") }
    }

    var ebayBrowseBaseURL: String { "https://api.ebay.com/buy/browse/v1" }
    var ebayAuthURL: String { "https://api.ebay.com/identity/v1/oauth2/token" }

    /// Use eBay sandbox instead of production
    var ebayUseSandbox: Bool {
        get { UserDefaults.standard.bool(forKey: "ebayUseSandbox") }
        set { UserDefaults.standard.set(newValue, forKey: "ebayUseSandbox") }
    }

    /// Configured either with Client ID + Secret (OAuth flow) or a direct App Token.
    var ebayIsConfigured: Bool {
        (!ebayClientID.isEmpty && !ebayClientSecret.isEmpty) || !ebayAppToken.isEmpty
    }

    // MARK: - Open Library
    var openLibraryBaseURL: String { "https://openlibrary.org" }
    var openLibraryCoversURL: String { "https://covers.openlibrary.org" }

    private init() {}
}
