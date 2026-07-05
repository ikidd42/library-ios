import Foundation

/// A pending watchlist item saved by the Share Extension and consumed by the main app.
struct PendingWatchItem: Codable, Identifiable {
    let id: UUID
    /// The numeric eBay item ID parsed from the listing URL.
    let ebayItemID: String
    /// The full eBay listing URL.
    let ebayListingURL: String
    /// The raw listing title captured from the share sheet (e.g. "Harry Potter Sorcerer's Stone HC 1st Ed").
    let listingTitle: String
    let addedAt: Date

    init(ebayItemID: String, ebayListingURL: String, listingTitle: String) {
        self.id = UUID()
        self.ebayItemID = ebayItemID
        self.ebayListingURL = ebayListingURL
        self.listingTitle = listingTitle
        self.addedAt = Date()
    }
}

/// Shared file-based container used to pass data between the Share Extension and the main app.
///
/// Both the main app target and the LibraryShareExtension target must have the same
/// App Group capability enabled in Xcode (Signing & Capabilities → App Groups).
/// Set `appGroupID` to match the group ID you configured there.
struct SharedContainer {

    // MARK: - Configuration

    /// Must match the App Group ID in Xcode for both the main app and share extension targets.
    static let appGroupID = "group.org.marinersmuseum.library"

    private static let pendingFileName = "pending_watch_items.json"

    // MARK: - URLs

    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var pendingFileURL: URL? {
        sharedContainerURL?.appendingPathComponent(pendingFileName)
    }

    // MARK: - Read

    static func readPendingItems() -> [PendingWatchItem] {
        print("[SharedContainer] App Group ID: \(appGroupID)")
        print("[SharedContainer] Container URL: \(sharedContainerURL?.path ?? "NIL — App Group not configured")")

        guard let url = pendingFileURL else {
            print("[SharedContainer] ❌ pendingFileURL is nil — App Group is not set up correctly")
            return []
        }
        print("[SharedContainer] Pending file path: \(url.path)")

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[SharedContainer] ℹ️ No pending file found — nothing was shared yet")
            return []
        }

        guard let data = try? Data(contentsOf: url) else {
            print("[SharedContainer] ❌ Could not read pending file data")
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let items = try? decoder.decode([PendingWatchItem].self, from: data) else {
            print("[SharedContainer] ❌ Failed to decode pending items. Raw contents: \(String(data: data, encoding: .utf8) ?? "<unreadable>")")
            return []
        }

        print("[SharedContainer] ✅ Read \(items.count) pending item(s):")
        for item in items {
            print("  • itemID=\(item.ebayItemID) title='\(item.listingTitle)' url=\(item.ebayListingURL)")
        }
        return items
    }

    // MARK: - Write

    static func appendPendingItem(_ item: PendingWatchItem) {
        var existing = readPendingItems()
        existing.append(item)
        write(existing)
    }

    static func clearPendingItems() {
        guard let url = pendingFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    private static func write(_ items: [PendingWatchItem]) {
        guard let url = pendingFileURL else {
            print("[SharedContainer] ❌ write() failed — pendingFileURL is nil")
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) {
            do {
                try data.write(to: url, options: .atomic)
                print("[SharedContainer] ✅ Wrote \(items.count) pending item(s) to \(url.path)")
            } catch {
                print("[SharedContainer] ❌ Write failed: \(error)")
            }
        } else {
            print("[SharedContainer] ❌ Failed to encode pending items")
        }
    }

    // MARK: - eBay URL Parsing

    /// Extracts the numeric eBay item ID from a listing URL.
    /// Handles formats like:
    ///   https://www.ebay.com/itm/1234567890
    ///   https://www.ebay.com/itm/some-title/1234567890
    ///   ebay://item?id=1234567890
    static func parseItemID(from url: URL) -> String? {
        let string = url.absoluteString

        // Standard web URL: /itm/<optional-title>/<id> or /itm/<id>
        if let range = string.range(of: #"/itm/(?:[^/]+/)?(\d{10,13})"#, options: .regularExpression) {
            let match = String(string[range])
            // Extract just the trailing numeric segment
            if let numRange = match.range(of: #"\d{10,13}$"#, options: .regularExpression) {
                return String(match[numRange])
            }
        }

        // Query parameter: ?id=<id>
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let idParam = components.queryItems?.first(where: { $0.name == "id" }) {
            return idParam.value
        }

        return nil
    }
}
