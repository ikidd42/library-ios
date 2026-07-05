import Foundation
import Observation

/// Coordinates book lookups across Google Books and Open Library,
/// with cover image downloading and caching.
@Observable
final class BookLookupService {
    private let googleBooks = GoogleBooksService()
    private let openLibrary = OpenLibraryService()
    private let ebayService = EbayPriceService()

    var isSearching = false
    var searchResults: [BookSearchResult] = []
    var errorMessage: String?

    // MARK: - Search by ISBN

    func searchByISBN(_ isbn: String) async {
        await performSearch {
            // Strategy 1: Google Books isbn: search (works for real ISBNs)
            let googleResults = (try? await self.googleBooks.searchByISBN(isbn)) ?? []
            if !googleResults.isEmpty {
                return googleResults
            }

            // Strategy 2: Open Library isbn search
            print("[BookLookup] Google Books isbn: search returned nothing, trying Open Library...")
            let olResults = (try? await self.openLibrary.searchByISBN(isbn)) ?? []
            if !olResults.isEmpty {
                return olResults
            }

            // Strategy 3: Plain number search on Google Books (handles UPC codes
            // and other non-ISBN barcodes — Google sometimes indexes these)
            print("[BookLookup] ISBN search failed, trying plain number search...")
            let plainResults = (try? await self.googleBooks.search(query: isbn, maxResults: 5)) ?? []
            if !plainResults.isEmpty {
                return plainResults
            }

            print("[BookLookup] No results for barcode \(isbn)")
            return []
        }
    }

    // MARK: - Search by Title/Author

    func searchByText(title: String?, author: String?) async {
        await performSearch {
            // Search both services concurrently
            async let googleResults = self.googleBooks.search(title: title, author: author)
            async let olResults = self.openLibrary.search(title: title, author: author)

            let google = (try? await googleResults) ?? []
            let ol = (try? await olResults) ?? []

            // Merge results, preferring Google Books (better metadata)
            return google + ol
        }
    }

    // MARK: - Free-text Search (for OCR results)

    /// Returns results directly without updating view state. Used for background enrichment.
    func searchFreeTextResults(_ text: String) async -> [BookSearchResult] {
        print("[BookLookup] searchFreeTextResults: '\(text)'")
        let googleResults = (try? await googleBooks.search(query: text, maxResults: 10)) ?? []
        if !googleResults.isEmpty {
            print("[BookLookup] Google Books returned \(googleResults.count) result(s)")
            return googleResults
        }
        print("[BookLookup] Google Books empty, trying Open Library")
        let olResults = (try? await openLibrary.search(title: text)) ?? []
        print("[BookLookup] Open Library returned \(olResults.count) result(s)")
        return olResults
    }

    func searchFreeText(_ text: String) async {
        await performSearch {
            let googleResults = (try? await self.googleBooks.search(query: text, maxResults: 15)) ?? []
            if !googleResults.isEmpty {
                return googleResults
            }
            // Fall back to Open Library title search
            return try await self.openLibrary.search(title: text)
        }
    }

    // MARK: - Download Cover Image

    func downloadCoverImage(from urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  data.count > 500 else { // Filter out tiny placeholder images
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    // MARK: - eBay Price Lookup

    func fetchEbayPrice(for book: Book) async -> EbayPriceResult? {
        do {
            return try await ebayService.fetchLowestPrice(
                isbn: book.isbn13 ?? book.isbn,
                title: book.title,
                author: book.authors
            )
        } catch {
            print("eBay price fetch error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetches the eBay listing title for a given item ID, reusing the cached OAuth token.
    func fetchEbayItemTitle(itemID: String) async -> String? {
        await ebayService.fetchItemTitle(itemID: itemID)
    }

    func fetchEbayPrice(for watchedBook: WatchedBook) async -> EbayPriceResult? {
        let isbn = watchedBook.isbn13 ?? watchedBook.isbn
        let title = watchedBook.title
        let author = watchedBook.authors
        print("[BookLookup] fetchEbayPrice(watched) — isbn=\(isbn ?? "nil") title='\(title)' author='\(author)'")
        do {
            let result = try await ebayService.fetchLowestPrice(isbn: isbn, title: title, author: author)
            if let result {
                print("[BookLookup] ✅ eBay result: \(result.formattedPrice) — '\(result.title)'")
            } else {
                print("[BookLookup] ⚠️ eBay returned no results for title='\(title)'")
            }
            return result
        } catch {
            print("[BookLookup] ❌ eBay fetch error: \(error)")
            return nil
        }
    }

    // MARK: - Create Book from Search Result

    func createBook(from result: BookSearchResult) async -> Book {
        let book = Book(
            title: result.title,
            authors: result.authors,
            isbn: result.isbn,
            isbn13: result.isbn13,
            publisher: result.publisher,
            publishedDate: result.publishedDate,
            bookDescription: result.description,
            pageCount: result.pageCount,
            categories: result.categories,
            language: result.language,
            coverImageURL: result.coverImageURL
        )

        // Download cover image
        if let coverURL = result.coverImageURL {
            book.coverImageData = await downloadCoverImage(from: coverURL)
        }

        return book
    }

    // MARK: - Private

    private func performSearch(_ search: @escaping () async throws -> [BookSearchResult]) async {
        await MainActor.run {
            isSearching = true
            errorMessage = nil
            searchResults = []
        }

        do {
            let results = try await search()
            await MainActor.run {
                searchResults = results
                isSearching = false
                if results.isEmpty {
                    errorMessage = "No books found"
                }
            }
        } catch {
            await MainActor.run {
                isSearching = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
