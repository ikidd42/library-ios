import Testing
@testable import Library

struct OCRServiceTests {

    private let service = OCRService()

    // MARK: - ISBN extraction

    @Test func extractsISBN13WithLabelAndHyphens() {
        let lines = ["Some Publisher", "ISBN 978-0-306-40615-7", "Printed in USA"]
        #expect(service.extractISBN(from: lines) == "9780306406157")
    }

    @Test func extractsBareISBN13() {
        let lines = ["9780441172719"]
        #expect(service.extractISBN(from: lines) == "9780441172719")
    }

    @Test func extractsISBN10WithLabel() {
        let lines = ["ISBN: 0-306-40615-2"]
        #expect(service.extractISBN(from: lines) == "0306406152")
    }

    @Test func extractsISBN10WithXCheckDigit() {
        let lines = ["ISBN 0-486-65088-X"]
        #expect(service.extractISBN(from: lines) == "048665088X")
    }

    @Test func returnsNilWhenNoISBNPresent() {
        let lines = ["The Hobbit", "by J.R.R. Tolkien", "Houghton Mifflin"]
        #expect(service.extractISBN(from: lines) == nil)
    }

    // MARK: - Title page parsing

    @Test func parsesTitleAndByAuthor() {
        let info = service.parseTitlePage(lines: ["THE HOBBIT", "by J.R.R. Tolkien"])
        #expect(info.title == "THE HOBBIT")
        #expect(info.author == "J.R.R. Tolkien")
        #expect(info.hasUsableInfo)
    }

    @Test func parsesAuthorWithWrittenByPrefix() {
        let info = service.parseTitlePage(lines: ["Dune", "written by Frank Herbert"])
        #expect(info.author == "Frank Herbert")
    }

    @Test func skipsCopyrightNoiseLines() {
        let info = service.parseTitlePage(lines: [
            "Copyright © 1965",
            "Dune",
            "Frank Herbert",
            "www.example.com"
        ])
        #expect(info.title == "Dune")
        #expect(info.rawText.contains("Copyright") == false)
    }

    @Test func buildsSearchQueriesMostSpecificFirst() {
        let info = service.parseTitlePage(lines: ["Emma", "by Jane Austen"])
        #expect(info.searchQueries.first == "Emma Jane Austen")
        #expect(info.searchQueries.contains("Emma"))
    }

    @Test func emptyInputHasNoUsableInfo() {
        let info = service.parseTitlePage(lines: [])
        #expect(!info.hasUsableInfo)
        #expect(info.searchQueries.isEmpty)
    }
}
