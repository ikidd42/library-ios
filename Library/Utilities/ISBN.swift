import Foundation

/// Utilities for working with ISBN-10 / ISBN-13 codes and scanned barcodes.
nonisolated enum ISBN {

    /// Strips everything except digits and the ISBN-10 check character "X".
    static func normalize(_ raw: String) -> String {
        raw.uppercased().filter { $0.isNumber || $0 == "X" }
    }

    /// Converts an ISBN-10 to its ISBN-13 equivalent by prepending 978
    /// and recomputing the check digit. Returns the input unchanged if the
    /// first 9 characters aren't all digits.
    static func isbn13(fromISBN10 isbn10: String) -> String {
        let digits = "978" + isbn10.prefix(9)
        var sum = 0
        for (index, char) in digits.enumerated() {
            guard let digit = char.wholeNumberValue else { return isbn10 }
            sum += (index % 2 == 0) ? digit : digit * 3
        }
        let check = (10 - (sum % 10)) % 10
        return digits + "\(check)"
    }

    /// Validates an ISBN-13 (EAN-13) check digit.
    static func isValidISBN13(_ code: String) -> Bool {
        guard code.count == 13, code.allSatisfy(\.isNumber) else { return false }
        var sum = 0
        for (index, char) in code.enumerated() {
            let digit = char.wholeNumberValue ?? 0
            sum += (index % 2 == 0) ? digit : digit * 3
        }
        return sum % 10 == 0
    }

    /// Validates an ISBN-10 check digit (the last character may be "X" for 10).
    static func isValidISBN10(_ code: String) -> Bool {
        let code = code.uppercased()
        guard code.count == 10 else { return false }
        var sum = 0
        for (index, char) in code.enumerated() {
            let value: Int
            if char == "X" && index == 9 {
                value = 10
            } else if char.isNumber, let digit = char.wholeNumberValue {
                value = digit
            } else {
                return false
            }
            sum += value * (10 - index)
        }
        return sum % 11 == 0
    }

    /// Interprets a scanned barcode payload as a code worth looking up.
    ///
    /// Bookland EAN-13 barcodes (978/979 prefix) are ISBNs, and ISBN-10s are
    /// converted to ISBN-13. UPC-A (12), other EAN-13, and EAN-8 retail codes
    /// are passed through so the lookup service can still try them.
    /// Returns nil for payloads that can't be a book code.
    static func lookupCode(fromScannedPayload payload: String) -> String? {
        let cleaned = normalize(payload)
        if cleaned.count == 13 && (cleaned.hasPrefix("978") || cleaned.hasPrefix("979")) {
            return cleaned
        }
        if cleaned.count == 10 {
            return isbn13(fromISBN10: cleaned)
        }
        if cleaned.count == 12 || cleaned.count == 13 || cleaned.count == 8 {
            return cleaned
        }
        return nil
    }
}
