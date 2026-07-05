import Foundation
import os

/// Centralized loggers, one per functional area. View logs in Console.app
/// or Xcode's console, filterable by subsystem/category.
nonisolated extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Library"

    static let books = Logger(subsystem: subsystem, category: "books")
    static let ebay = Logger(subsystem: subsystem, category: "ebay")
    static let ocr = Logger(subsystem: subsystem, category: "ocr")
    static let watchlist = Logger(subsystem: subsystem, category: "watchlist")
    static let export = Logger(subsystem: subsystem, category: "export")
}
