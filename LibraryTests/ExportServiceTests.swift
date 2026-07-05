import Testing
import Foundation
import SwiftData
@testable import Library

@MainActor
struct ExportServiceTests {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Book.self, PriceHistoryEntry.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeBooks(in context: ModelContext) -> [Book] {
        let plain = Book(title: "Dune", authors: "Frank Herbert", isbn13: "9780441172719", pageCount: 412)
        plain.rating = 5

        // Title with a comma and quotes — exercises CSV escaping
        let tricky = Book(
            title: "Slaughterhouse-Five, or \"The Children's Crusade\"",
            authors: "Kurt Vonnegut"
        )
        tricky.personalNotes = "Line one\nLine two"
        tricky.ebayLowestPrice = 12.5

        let books = [plain, tricky]
        books.forEach { context.insert($0) }
        return books
    }

    // MARK: - CSV

    @Test func csvHasHeaderPlusOneRowPerBook() throws {
        let context = try makeContext()
        let books = makeBooks(in: context)

        let csv = ExportService.export(books: books, format: .csv)
        // The tricky book has an embedded newline, so count logical records
        // by parsing quoted fields rather than splitting on every newline.
        let records = parseCSVRecords(csv)
        #expect(records.count == books.count + 1)
    }

    @Test func csvEscapesCommasQuotesAndNewlines() throws {
        let context = try makeContext()
        let books = makeBooks(in: context)

        let csv = ExportService.export(books: books, format: .csv)
        #expect(csv.contains(#""Slaughterhouse-Five, or ""The Children's Crusade""""#))
        #expect(csv.contains("\"Line one\nLine two\""))
    }

    @Test func csvColumnsMatchHeaderCount() throws {
        let context = try makeContext()
        let books = makeBooks(in: context)

        let csv = ExportService.export(books: books, format: .csv)
        let records = parseCSVRecords(csv)
        let headerColumns = records[0].count
        for record in records {
            #expect(record.count == headerColumns)
        }
    }

    // MARK: - JSON

    @Test func jsonIsValidAndRoundTrips() throws {
        let context = try makeContext()
        let books = makeBooks(in: context)

        let json = ExportService.export(books: books, format: .json)
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let wrapper = try #require(object)

        #expect(wrapper["bookCount"] as? Int == books.count)

        let exported = try #require(wrapper["books"] as? [[String: Any]])
        let titles = Set(exported.compactMap { $0["title"] as? String })
        #expect(titles.contains("Dune"))
    }

    @Test func jsonOmitsNilFields() throws {
        let context = try makeContext()
        let book = Book(title: "Minimal", authors: "Nobody")
        context.insert(book)

        let json = ExportService.export(books: [book], format: .json)
        let wrapper = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let exported = try #require(wrapper["books"] as? [[String: Any]])

        #expect(exported[0]["isbn"] == nil)
        #expect(exported[0]["ebayLowestPrice"] == nil)
        #expect(exported[0]["title"] as? String == "Minimal")
    }

    @Test func jsonIncludesPriceHistory() throws {
        let context = try makeContext()
        let book = Book(title: "Priced", authors: "Someone")
        context.insert(book)
        book.priceHistory.append(PriceHistoryEntry(price: 9.99))

        let json = ExportService.export(books: [book], format: .json)
        let wrapper = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let exported = try #require(wrapper["books"] as? [[String: Any]])
        let history = try #require(exported[0]["priceHistory"] as? [[String: Any]])

        #expect(history.count == 1)
        #expect(history[0]["price"] as? Double == 9.99)
    }

    // MARK: - Minimal CSV parser (quotes-aware) for assertions

    private func parseCSVRecords(_ csv: String) -> [[String]] {
        var records: [[String]] = []
        var field = ""
        var record: [String] = []
        var inQuotes = false
        var iterator = csv.makeIterator()

        while let char = iterator.next() {
            if inQuotes {
                if char == "\"" {
                    inQuotes = false
                } else {
                    field.append(char)
                }
            } else {
                switch char {
                case "\"": inQuotes = true
                case ",":  record.append(field); field = ""
                case "\n": record.append(field); field = ""; records.append(record); record = []
                default:   field.append(char)
                }
            }
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records
    }
}
