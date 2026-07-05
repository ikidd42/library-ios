import Testing
import SwiftData
@testable import Library

@MainActor
struct DuplicateDetectorTests {

    /// In-memory SwiftData container so Book models behave like they do in the app.
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Book.self, PriceHistoryEntry.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeLibrary(in context: ModelContext) -> [Book] {
        let books = [
            Book(title: "The Hobbit", authors: "J.R.R. Tolkien", isbn: "0345339681", isbn13: "9780345339683"),
            Book(title: "Dune", authors: "Frank Herbert", isbn13: "9780441172719"),
            Book(title: "Emma", authors: "Jane Austen"),
        ]
        books.forEach { context.insert($0) }
        return books
    }

    @Test func matchesByISBN13() throws {
        let context = try makeContext()
        let books = makeLibrary(in: context)

        let match = DuplicateDetector.findDuplicate(
            in: books, title: "Different Title", authors: "Someone Else",
            isbn: nil, isbn13: "9780441172719"
        )
        #expect(match?.title == "Dune")
    }

    @Test func matchesISBN10AgainstEitherField() throws {
        let context = try makeContext()
        let books = makeLibrary(in: context)

        let match = DuplicateDetector.findDuplicate(
            in: books, title: "Whatever", authors: "",
            isbn: "0345339681", isbn13: nil
        )
        #expect(match?.title == "The Hobbit")
    }

    @Test func matchesTitleAndAuthorCaseInsensitively() throws {
        let context = try makeContext()
        let books = makeLibrary(in: context)

        let match = DuplicateDetector.findDuplicate(
            in: books, title: "  EMMA ", authors: "jane austen",
            isbn: nil, isbn13: nil
        )
        #expect(match?.title == "Emma")
    }

    @Test func sameTitleDifferentAuthorIsNotADuplicate() throws {
        let context = try makeContext()
        let books = makeLibrary(in: context)

        let match = DuplicateDetector.findDuplicate(
            in: books, title: "Emma", authors: "Someone Else",
            isbn: nil, isbn13: nil
        )
        #expect(match == nil)
    }

    @Test func noMatchReturnsNil() throws {
        let context = try makeContext()
        let books = makeLibrary(in: context)

        let match = DuplicateDetector.findDuplicate(
            in: books, title: "Brand New Book", authors: "New Author",
            isbn: "1111111111", isbn13: "9781111111111"
        )
        #expect(match == nil)
    }

    @Test func searchResultOverloadMatches() throws {
        let context = try makeContext()
        let books = makeLibrary(in: context)

        let result = BookSearchResult(
            title: "Dune", authors: "Frank Herbert",
            isbn: nil, isbn13: "9780441172719",
            publisher: nil, publishedDate: nil, description: nil,
            pageCount: nil, categories: nil, language: nil,
            coverImageURL: nil, source: .googleBooks
        )
        let match = DuplicateDetector.findDuplicate(in: books, for: result)
        #expect(match?.title == "Dune")
    }
}
