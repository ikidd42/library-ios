import SwiftUI
import SwiftData

/// Displays all watched books and their current eBay market prices.
/// Books can be added by sharing an eBay listing or via the + button to search manually.
struct WatchlistView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WatchedBook.dateAdded, order: .reverse) private var watchedBooks: [WatchedBook]

    @State private var lookupService = BookLookupService()
    @State private var isRefreshing = false
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            List {
                // Summary card
                if !watchedBooks.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Watching \(watchedBooks.count) book\(watchedBooks.count == 1 ? "" : "s")")
                                .font(.headline)
                            if let total = totalValue {
                                Text("Combined lowest price: \(formatPrice(total))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Watched books list
                ForEach(watchedBooks) { book in
                    NavigationLink(destination: WatchedBookDetailView(book: book)) {
                        watchRow(book)
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationTitle("Watchlist")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .refreshable {
                await refreshAllPrices()
            }
            .overlay {
                if watchedBooks.isEmpty {
                    ContentUnavailableView {
                        Label("No Watched Books", systemImage: "eye")
                    } description: {
                        Text("Share an eBay listing to the Library app, or tap + to search for a book to track.")
                    } actions: {
                        Button("Add a Book") { showAddSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            // Ingest on first load
            .task { await ingestPendingItems() }
            // Also ingest whenever the app returns to the foreground (e.g. after sharing from eBay)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await ingestPendingItems() }
            }
            .sheet(isPresented: $showAddSheet) {
                WatchlistSearchSheet { result in
                    Task { await addWatchedBook(from: result) }
                }
            }
        }
    }

    // MARK: - Row

    private func watchRow(_ book: WatchedBook) -> some View {
        HStack(spacing: 12) {
            WatchedBookCoverView(book: book, width: 35, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(book.authors.isEmpty ? "Unknown Author" : book.authors)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let price = book.ebayLowestPrice {
                    Text(formatPrice(price))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    if let updated = book.ebayPriceLastUpdated {
                        Text(updated.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("No price yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private var totalValue: Double? {
        let prices = watchedBooks.compactMap(\.ebayLowestPrice)
        guard !prices.isEmpty else { return nil }
        return prices.reduce(0, +)
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(watchedBooks[index])
        }
    }

    /// Batch-refreshes lowest eBay prices for all watched books.
    private func refreshAllPrices() async {
        isRefreshing = true
        for book in watchedBooks {
            if let result = await lookupService.fetchEbayPrice(for: book) {
                book.ebayLowestPrice = result.lowestPrice
                book.ebaySearchURL = result.searchResultsURL
                book.ebayPriceLastUpdated = Date()
                let entry = WatchedPriceEntry(price: result.lowestPrice, currency: result.currency)
                book.priceHistory.append(entry)
            }
            // Respect eBay rate limits
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        isRefreshing = false
    }

    /// Reads items queued by the Share Extension and creates WatchedBook records.
    @MainActor
    private func ingestPendingItems() async {
        print("[Watchlist] ingestPendingItems() called")
        let pending = SharedContainer.readPendingItems()
        guard !pending.isEmpty else {
            print("[Watchlist] No pending items to ingest")
            return
        }
        print("[Watchlist] Ingesting \(pending.count) item(s)...")
        SharedContainer.clearPendingItems()

        for item in pending {
            // Insert a placeholder immediately so the row appears in the list
            let watched = WatchedBook(
                title: item.listingTitle,
                ebayItemID: item.ebayItemID,
                ebayListingURL: item.ebayListingURL
            )
            modelContext.insert(watched)
            print("[Watchlist] ✅ Inserted placeholder: '\(item.listingTitle)'")

            // Enrich asynchronously: real eBay title → Google Books metadata → price lookup
            Task { @MainActor in
                await enrichWatchedBook(watched, from: item)
            }
        }
    }

    /// Full enrichment pipeline for a just-shared eBay item:
    /// 1. Fetch real listing title from eBay item endpoint
    /// 2. Search Google Books / Open Library for clean book metadata
    /// 3. Fetch lowest eBay market price using the clean metadata
    private func enrichWatchedBook(_ watched: WatchedBook, from item: PendingWatchItem) async {
        // Step 1: Get the real listing title from eBay
        let listingTitle = await lookupService.fetchEbayItemTitle(itemID: item.ebayItemID) ?? item.listingTitle
        let cleanedTitle = cleanEbayTitle(listingTitle)
        print("[Watchlist] eBay listing title: '\(listingTitle)'")
        print("[Watchlist] Cleaned for search: '\(cleanedTitle)'")

        // Step 2: Find the actual book in Google Books / Open Library
        let searchTitle = cleanedTitle.isEmpty ? listingTitle : cleanedTitle
        let bookResults = await lookupService.searchFreeTextResults(searchTitle)

        if let match = bookResults.first {
            print("[Watchlist] ✅ Book match: '\(match.title)' by \(match.authors)")
            watched.title = match.title
            watched.authors = match.authors
            watched.isbn = match.isbn
            watched.isbn13 = match.isbn13
            watched.coverImageURL = match.coverImageURL
            if let coverURL = match.coverImageURL {
                watched.coverImageData = await lookupService.downloadCoverImage(from: coverURL)
            }
        } else {
            print("[Watchlist] ⚠️ No book match found, keeping cleaned title")
            watched.title = searchTitle
        }

        // Step 3: Now price-lookup with proper title / author / ISBN
        print("[Watchlist] Fetching price for '\(watched.title)' by '\(watched.authors)'")
        if let result = await lookupService.fetchEbayPrice(for: watched) {
            print("[Watchlist] ✅ Price: \(result.formattedPrice)")
            watched.ebayLowestPrice = result.lowestPrice
            watched.ebaySearchURL = result.searchResultsURL
            watched.ebayPriceLastUpdated = Date()
            watched.priceHistory.append(
                WatchedPriceEntry(price: result.lowestPrice, currency: result.currency)
            )
        } else {
            print("[Watchlist] ⚠️ Price fetch returned nil (isbn=\(watched.isbn13 ?? watched.isbn ?? "none"), authors='\(watched.authors)')")
        }
    }

    /// Strips common eBay listing noise to produce a cleaner title for display and search.
    /// Input:  "Harry Potter Sorcerer's Stone HC DJ 1st Ed/1st Print SIGNED Rowling"
    /// Output: "Harry Potter Sorcerer's Stone Rowling"
    private func cleanEbayTitle(_ raw: String) -> String {
        var s = raw

        // Strip trailing "| eBay" / "- eBay"
        s = s.replacingOccurrences(of: #"\s*[|\-]\s*eBay\b"#, with: "", options: .regularExpression)

        // Strip year patterns like "(1997)" or "(2001, Hardcover)"
        s = s.replacingOccurrences(of: #"\(\d{4}[^)]*\)"#, with: " ", options: .regularExpression)

        // Strip edition / printing noise
        s = s.replacingOccurrences(
            of: #"\b(\d+(st|nd|rd|th)|First|Second|Third)\s+(Edition|Printing|Print|Ed\.?)\b"#,
            with: " ", options: [.regularExpression, .caseInsensitive])

        // Strip format indicators
        let formatWords = [#"\bH[CD]\b"#, #"\bHB\b"#, #"\bDJ\b"#, #"\bPB\b"#,
                           #"\bHardcover\b"#, #"\bPaperback\b"#, #"\bSoftcover\b"#,
                           #"\bMass\s+Market\b"#]
        for pattern in formatWords {
            s = s.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }

        // Strip condition / collectible markers
        let conditionWords = [#"\bSigned\b"#, #"\bRARE\b"#, #"\bOOP\b"#, #"\bVintage\b"#,
                              #"\bEx[\s\-]?Library\b"#, #"\bBook\s+Club\b"#,
                              #"\bNear\s+Fine\b"#, #"\bVG\+?\b"#, #"\bOut\s+of\s+Print\b"#,
                              #"\bIllustrated\b"#, #"\bLot\s+of\s+\d+\b"#]
        for pattern in conditionWords {
            s = s.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }

        // Collapse whitespace
        return s.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Adds a book from a manual search result to the watchlist.
    private func addWatchedBook(from result: BookSearchResult) async {
        let watched = WatchedBook(
            title: result.title,
            authors: result.authors,
            isbn: result.isbn,
            isbn13: result.isbn13,
            coverImageURL: result.coverImageURL
        )

        if let result = await lookupService.fetchEbayPrice(for: watched) {
            watched.ebayLowestPrice = result.lowestPrice
            watched.ebaySearchURL = result.searchResultsURL
            watched.ebayPriceLastUpdated = Date()
            watched.priceHistory.append(
                WatchedPriceEntry(price: result.lowestPrice, currency: result.currency)
            )
        }

        modelContext.insert(watched)
    }

    private func formatPrice(_ price: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: price)) ?? "$\(price)"
    }
}
