import Testing
@testable import Library

struct EbayTitleCleanerTests {

    @Test func stripsTrailingEbaySuffix() {
        #expect(EbayTitleCleaner.clean("The Hobbit | eBay") == "The Hobbit")
        #expect(EbayTitleCleaner.clean("The Hobbit - eBay") == "The Hobbit")
    }

    @Test func stripsYearParentheticals() {
        #expect(EbayTitleCleaner.clean("The Hobbit (1997)") == "The Hobbit")
        #expect(EbayTitleCleaner.clean("The Hobbit (2001, Hardcover)") == "The Hobbit")
    }

    @Test func stripsEditionNoise() {
        #expect(EbayTitleCleaner.clean("Dune 1st Edition Frank Herbert") == "Dune Frank Herbert")
        #expect(EbayTitleCleaner.clean("Dune First Printing Frank Herbert") == "Dune Frank Herbert")
    }

    @Test func stripsFormatIndicators() {
        #expect(EbayTitleCleaner.clean("Dune HC DJ Frank Herbert") == "Dune Frank Herbert")
        #expect(EbayTitleCleaner.clean("Dune Paperback Frank Herbert") == "Dune Frank Herbert")
        #expect(EbayTitleCleaner.clean("Dune Mass Market PB") == "Dune")
    }

    @Test func stripsConditionMarkers() {
        #expect(EbayTitleCleaner.clean("1984 George Orwell SIGNED") == "1984 George Orwell")
        #expect(EbayTitleCleaner.clean("1984 George Orwell VG+ Vintage") == "1984 George Orwell")
        #expect(EbayTitleCleaner.clean("1984 RARE OOP George Orwell") == "1984 George Orwell")
    }

    @Test func collapsesWhitespace() {
        #expect(EbayTitleCleaner.clean("  The   Hobbit   ") == "The Hobbit")
    }

    @Test func leavesCleanTitlesAlone() {
        #expect(EbayTitleCleaner.clean("Pride and Prejudice Jane Austen") == "Pride and Prejudice Jane Austen")
    }

    @Test func handlesRealisticListingTitle() {
        let cleaned = EbayTitleCleaner.clean(
            "Harry Potter Sorcerer's Stone HC DJ SIGNED Rowling (1998) | eBay"
        )
        #expect(cleaned == "Harry Potter Sorcerer's Stone Rowling")
    }
}
