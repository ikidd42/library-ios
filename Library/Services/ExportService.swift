import Foundation
import os

/// Generates CSV or JSON exports of the library
struct ExportService {

    enum ExportFormat: String, CaseIterable, Identifiable {
        case csv = "CSV"
        case json = "JSON"

        var id: String { rawValue }

        var fileExtension: String {
            switch self {
            case .csv: return "csv"
            case .json: return "json"
            }
        }

        var mimeType: String {
            switch self {
            case .csv: return "text/csv"
            case .json: return "application/json"
            }
        }
    }

    static func export(books: [Book], format: ExportFormat) -> String {
        switch format {
        case .csv:
            return generateCSV(books: books)
        case .json:
            return generateJSON(books: books)
        }
    }

    static func exportToFile(books: [Book], format: ExportFormat) -> URL? {
        let content = export(books: books, format: format)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        let filename = "LibraryBackup_\(dateString).\(format.fileExtension)"

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            Logger.export.error("Failed to write export file: \(error)")
            return nil
        }
    }

    // MARK: - CSV

    private static func generateCSV(books: [Book]) -> String {
        var lines: [String] = []

        // Header
        let headers = [
            "Title", "Authors", "ISBN", "ISBN-13", "Publisher", "Published Date",
            "Pages", "Categories", "Language", "Reading Status",
            "Date Added", "Date Started", "Date Finished",
            "Rating", "Copies", "Personal Notes",
            "eBay Lowest Price", "eBay Price URL", "eBay Price Last Updated"
        ]
        lines.append(headers.joined(separator: ","))

        // Rows
        let dateFormatter = ISO8601DateFormatter()

        for book in books {
            let fields: [String] = [
                csvEscape(book.title),
                csvEscape(book.authors),
                csvEscape(book.isbn ?? ""),
                csvEscape(book.isbn13 ?? ""),
                csvEscape(book.publisher ?? ""),
                csvEscape(book.publishedDate ?? ""),
                book.pageCount.map { "\($0)" } ?? "",
                csvEscape(book.categories ?? ""),
                csvEscape(book.language ?? ""),
                csvEscape(book.readingStatusEnum.rawValue),
                dateFormatter.string(from: book.dateAdded),
                book.dateStartedReading.map { dateFormatter.string(from: $0) } ?? "",
                book.dateFinishedReading.map { dateFormatter.string(from: $0) } ?? "",
                book.rating.map { "\($0)" } ?? "",
                "\(book.copyCount)",
                csvEscape(book.personalNotes ?? ""),
                book.ebayLowestPrice.map { String(format: "%.2f", $0) } ?? "",
                csvEscape(book.ebayPriceURL ?? ""),
                book.ebayPriceLastUpdated.map { dateFormatter.string(from: $0) } ?? ""
            ]
            lines.append(fields.joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    // MARK: - JSON

    private static func generateJSON(books: [Book]) -> String {
        let dateFormatter = ISO8601DateFormatter()

        let exportData = books.map { book -> [String: Any] in
            var dict: [String: Any] = [
                "title": book.title,
                "authors": book.authors,
                "readingStatus": book.readingStatusEnum.rawValue,
                "dateAdded": dateFormatter.string(from: book.dateAdded),
                "copyCount": book.copyCount
            ]

            if let isbn = book.isbn { dict["isbn"] = isbn }
            if let isbn13 = book.isbn13 { dict["isbn13"] = isbn13 }
            if let publisher = book.publisher { dict["publisher"] = publisher }
            if let publishedDate = book.publishedDate { dict["publishedDate"] = publishedDate }
            if let pages = book.pageCount { dict["pageCount"] = pages }
            if let categories = book.categories { dict["categories"] = categories }
            if let language = book.language { dict["language"] = language }
            if let rating = book.rating { dict["rating"] = rating }
            if let notes = book.personalNotes { dict["personalNotes"] = notes }
            if let start = book.dateStartedReading { dict["dateStartedReading"] = dateFormatter.string(from: start) }
            if let end = book.dateFinishedReading { dict["dateFinishedReading"] = dateFormatter.string(from: end) }
            if let price = book.ebayLowestPrice { dict["ebayLowestPrice"] = price }
            if let url = book.ebayPriceURL { dict["ebayPriceURL"] = url }
            if let updated = book.ebayPriceLastUpdated { dict["ebayPriceLastUpdated"] = dateFormatter.string(from: updated) }
            if let coverURL = book.coverImageURL { dict["coverImageURL"] = coverURL }

            // Price history
            if !book.priceHistory.isEmpty {
                dict["priceHistory"] = book.priceHistory.map { entry in
                    [
                        "price": entry.price,
                        "currency": entry.currency,
                        "fetchedAt": dateFormatter.string(from: entry.fetchedAt)
                    ] as [String : Any]
                }
            }

            return dict
        }

        let wrapper: [String: Any] = [
            "exportDate": dateFormatter.string(from: Date()),
            "bookCount": books.count,
            "books": exportData
        ]

        if let data = try? JSONSerialization.data(withJSONObject: wrapper, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }

        return "{\"error\": \"Failed to generate JSON\"}"
    }
}
