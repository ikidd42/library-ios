import Foundation
import SwiftData

/// Checks for duplicate books before adding to the library
struct DuplicateDetector {

    /// Find a duplicate book in the library matching by ISBN or title+author
    static func findDuplicate(in books: [Book], title: String, authors: String, isbn: String?, isbn13: String?) -> Book? {
        // Strategy 1: Exact ISBN-13 match
        if let isbn13 = isbn13, !isbn13.isEmpty {
            if let match = books.first(where: { $0.isbn13 == isbn13 }) {
                return match
            }
        }

        // Strategy 2: Exact ISBN match
        if let isbn = isbn, !isbn.isEmpty {
            if let match = books.first(where: { $0.isbn == isbn || $0.isbn13 == isbn }) {
                return match
            }
        }

        // Strategy 3: Case-insensitive title + author match
        let normalizedTitle = title.lowercased().trimmingCharacters(in: .whitespaces)
        let normalizedAuthor = authors.lowercased().trimmingCharacters(in: .whitespaces)

        if !normalizedTitle.isEmpty {
            if let match = books.first(where: {
                $0.title.lowercased().trimmingCharacters(in: .whitespaces) == normalizedTitle &&
                $0.authors.lowercased().trimmingCharacters(in: .whitespaces) == normalizedAuthor
            }) {
                return match
            }
        }

        return nil
    }

    /// Find a duplicate from a BookSearchResult
    static func findDuplicate(in books: [Book], for result: BookSearchResult) -> Book? {
        return findDuplicate(
            in: books,
            title: result.title,
            authors: result.authors,
            isbn: result.isbn,
            isbn13: result.isbn13
        )
    }
}
