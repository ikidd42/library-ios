import Foundation

/// Strips common eBay listing noise from a listing title to produce a cleaner
/// string for display and book search.
///
/// Input:  "Harry Potter Sorcerer's Stone HC DJ 1st Ed/1st Print SIGNED Rowling (1997) | eBay"
/// Output: "Harry Potter Sorcerer's Stone Rowling"
nonisolated enum EbayTitleCleaner {

    static func clean(_ raw: String) -> String {
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
}
