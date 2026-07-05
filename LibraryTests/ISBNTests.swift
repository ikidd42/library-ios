import Testing
@testable import Library

struct ISBNTests {

    // MARK: - Normalization

    @Test func normalizeStripsSeparators() {
        #expect(ISBN.normalize("978-0-306-40615-7") == "9780306406157")
        #expect(ISBN.normalize("0 306 40615 2") == "0306406152")
    }

    @Test func normalizeUppercasesCheckCharacter() {
        #expect(ISBN.normalize("048665088x") == "048665088X")
    }

    @Test func normalizeDropsNonISBNCharacters() {
        #expect(ISBN.normalize("ISBN: 9780306406157") == "9780306406157")
    }

    // MARK: - ISBN-10 → ISBN-13 conversion

    @Test func convertsKnownISBN10() {
        // Canonical example: 0-306-40615-2 → 978-0-306-40615-7
        #expect(ISBN.isbn13(fromISBN10: "0306406152") == "9780306406157")
    }

    @Test func convertedISBN13HasValidCheckDigit() {
        for isbn10 in ["0306406152", "0439420891", "0486650880"] {
            let isbn13 = ISBN.isbn13(fromISBN10: isbn10)
            #expect(ISBN.isValidISBN13(isbn13), "converted \(isbn10) → \(isbn13)")
        }
    }

    @Test func conversionReturnsInputWhenNotNumeric() {
        #expect(ISBN.isbn13(fromISBN10: "not-an-isbn") == "not-an-isbn")
    }

    // MARK: - Validation

    @Test func validatesISBN13CheckDigit() {
        #expect(ISBN.isValidISBN13("9780306406157"))
        #expect(!ISBN.isValidISBN13("9780306406158")) // wrong check digit
        #expect(!ISBN.isValidISBN13("97803064061"))   // wrong length
    }

    @Test func validatesISBN10CheckDigit() {
        #expect(ISBN.isValidISBN10("0306406152"))
        #expect(!ISBN.isValidISBN10("0306406153")) // wrong check digit
    }

    @Test func validatesISBN10WithXCheckCharacter() {
        #expect(ISBN.isValidISBN10("048665088X"))
        #expect(ISBN.isValidISBN10("048665088x")) // case-insensitive
        #expect(!ISBN.isValidISBN10("X486650880")) // X only valid in last position
    }

    // MARK: - Scanned barcode interpretation

    @Test func booklandEAN13PassesThrough() {
        #expect(ISBN.lookupCode(fromScannedPayload: "9780306406157") == "9780306406157")
        #expect(ISBN.lookupCode(fromScannedPayload: "9791234567896") == "9791234567896")
    }

    @Test func isbn10IsConvertedToISBN13() {
        #expect(ISBN.lookupCode(fromScannedPayload: "0306406152") == "9780306406157")
    }

    @Test func retailCodesPassThroughForLookup() {
        // UPC-A (12 digits) and EAN-8 aren't ISBNs but are worth a lookup attempt
        #expect(ISBN.lookupCode(fromScannedPayload: "036000291452") == "036000291452")
        #expect(ISBN.lookupCode(fromScannedPayload: "12345670") == "12345670")
    }

    @Test func junkPayloadsAreRejected() {
        #expect(ISBN.lookupCode(fromScannedPayload: "12345") == nil)
        #expect(ISBN.lookupCode(fromScannedPayload: "") == nil)
        #expect(ISBN.lookupCode(fromScannedPayload: "hello world") == nil)
    }

    @Test func scannedPayloadWithSeparatorsIsNormalized() {
        #expect(ISBN.lookupCode(fromScannedPayload: "978-0-306-40615-7") == "9780306406157")
    }
}
