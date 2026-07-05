import Foundation

nonisolated extension Double {
    /// Formats a price value as localized currency (e.g. "$12.99").
    func formattedAsPrice(currency: String = "USD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: self)) ?? "$\(self)"
    }
}
