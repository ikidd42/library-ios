import Testing
import Foundation
@testable import Library

struct APIModelDecodingTests {

    // MARK: - Google Books

    @Test func decodesGoogleBooksResponse() throws {
        let json = """
        {
          "totalItems": 1,
          "items": [{
            "id": "abc123",
            "volumeInfo": {
              "title": "The Hobbit",
              "authors": ["J.R.R. Tolkien"],
              "publisher": "Houghton Mifflin",
              "publishedDate": "1937",
              "pageCount": 310,
              "language": "en",
              "industryIdentifiers": [
                {"type": "ISBN_10", "identifier": "0345339681"},
                {"type": "ISBN_13", "identifier": "9780345339683"}
              ],
              "imageLinks": {
                "smallThumbnail": "http://books.google.com/small.jpg",
                "thumbnail": "http://books.google.com/thumb.jpg"
              }
            }
          }]
        }
        """
        let response = try JSONDecoder().decode(GoogleBooksResponse.self, from: Data(json.utf8))
        let info = try #require(response.items?.first?.volumeInfo)

        #expect(info.title == "The Hobbit")
        #expect(info.authors == ["J.R.R. Tolkien"])
        #expect(info.industryIdentifiers?.first(where: { $0.type == "ISBN_13" })?.identifier == "9780345339683")
    }

    @Test func googleImageLinksPreferThumbnailAndUpgradeToHTTPS() throws {
        let links = try JSONDecoder().decode(GoogleImageLinks.self, from: Data("""
        {"smallThumbnail": "http://example.com/small.jpg", "thumbnail": "http://example.com/thumb.jpg"}
        """.utf8))
        #expect(links.bestURL == "https://example.com/thumb.jpg")
    }

    @Test func googleImageLinksFallBackToSmallThumbnail() throws {
        let links = try JSONDecoder().decode(GoogleImageLinks.self, from: Data("""
        {"smallThumbnail": "https://example.com/small.jpg"}
        """.utf8))
        #expect(links.bestURL == "https://example.com/small.jpg")
    }

    @Test func decodesEmptyGoogleBooksResponse() throws {
        let response = try JSONDecoder().decode(GoogleBooksResponse.self, from: Data(#"{"totalItems": 0}"#.utf8))
        #expect(response.items == nil)
    }

    // MARK: - Open Library

    @Test func decodesOpenLibrarySnakeCaseKeys() throws {
        let json = """
        {
          "docs": [{
            "title": "Dune",
            "author_name": ["Frank Herbert"],
            "first_publish_year": 1965,
            "number_of_pages_median": 412,
            "cover_i": 12345,
            "isbn": ["9780441172719", "0441172717"]
          }]
        }
        """
        let response = try JSONDecoder().decode(OpenLibrarySearchResponse.self, from: Data(json.utf8))
        let doc = try #require(response.docs?.first)

        #expect(doc.title == "Dune")
        #expect(doc.authorName == ["Frank Herbert"])
        #expect(doc.firstPublishYear == 1965)
        #expect(doc.numberOfPagesMedian == 412)
        #expect(doc.coverI == 12345)
    }

    // MARK: - eBay

    @Test func decodesEbaySearchResponse() throws {
        let json = """
        {
          "itemSummaries": [{
            "title": "The Hobbit First Edition",
            "price": {"value": "24.99", "currency": "USD"},
            "itemWebUrl": "https://www.ebay.com/itm/1234567890",
            "condition": "Very Good"
          }]
        }
        """
        let response = try JSONDecoder().decode(EbaySearchResponse.self, from: Data(json.utf8))
        let item = try #require(response.itemSummaries?.first)

        #expect(item.price?.doubleValue == 24.99)
        #expect(item.condition == "Very Good")
    }

    @Test func ebayPriceHandlesUnparseableValue() throws {
        let price = try JSONDecoder().decode(EbayPrice.self, from: Data(#"{"value": "not-a-number", "currency": "USD"}"#.utf8))
        #expect(price.doubleValue == nil)
    }

    @Test func decodesEbayTokenResponseSnakeCaseKeys() throws {
        let json = #"{"access_token": "v1.abc", "expires_in": 7200, "token_type": "Bearer"}"#
        let token = try JSONDecoder().decode(EbayTokenResponse.self, from: Data(json.utf8))
        #expect(token.accessToken == "v1.abc")
        #expect(token.expiresIn == 7200)
    }

    // MARK: - Price formatting

    @Test func formatsUSDPrices() {
        #expect(12.99.formattedAsPrice() == "$12.99")
        #expect(1000.0.formattedAsPrice() == "$1,000.00")
    }
}
