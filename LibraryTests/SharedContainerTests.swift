import Testing
import Foundation
@testable import Library

struct SharedContainerParseItemIDTests {

    private func parse(_ urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        return SharedContainer.parseItemID(from: url)
    }

    @Test func parsesBareItemURL() {
        #expect(parse("https://www.ebay.com/itm/1234567890") == "1234567890")
    }

    @Test func parsesItemURLWithTitleSlug() {
        #expect(parse("https://www.ebay.com/itm/harry-potter-first-edition/123456789012") == "123456789012")
    }

    @Test func parsesItemURLWithQueryString() {
        #expect(parse("https://www.ebay.com/itm/1234567890?hash=abc&var=0") == "1234567890")
    }

    @Test func parsesCustomSchemeWithIDParameter() {
        #expect(parse("ebay://item?id=1234567890") == "1234567890")
    }

    @Test func returnsNilForNonListingURL() {
        #expect(parse("https://www.ebay.com/sch/i.html?_nkw=books") == nil)
        #expect(parse("https://www.example.com") == nil)
    }

    @Test func rejectsTooShortItemIDs() {
        // Item IDs are 10–13 digits; shorter numeric segments aren't item IDs
        #expect(parse("https://www.ebay.com/itm/123") == nil)
    }
}
