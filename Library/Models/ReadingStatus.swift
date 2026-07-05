import Foundation

/// Reading status for tracking book progress
enum ReadingStatus: String, Codable, CaseIterable, Identifiable {
    case wantToRead = "Want to Read"
    case reading = "Reading"
    case read = "Read"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .wantToRead: return "bookmark"
        case .reading: return "book.fill"
        case .read: return "checkmark.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .wantToRead: return "orange"
        case .reading: return "blue"
        case .read: return "green"
        }
    }
}
