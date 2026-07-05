import Foundation
import Vision
import UIKit

/// Extracts text from images using Apple's Vision framework,
/// then parses it to identify book title and author for API lookup.
/// Uses text bounding box size and position as signals — larger, higher
/// text on a title page is more likely to be the title.
final class OCRService {

    // MARK: - Rich Text Recognition

    /// Recognized line with metadata about size and position
    struct RecognizedLine {
        let text: String
        let confidence: Float
        let boundingBox: CGRect   // normalized 0-1, origin bottom-left
        let height: CGFloat       // height of bounding box (proxy for font size)

        /// Vertical center in top-down coordinates (0 = top of image)
        var verticalPosition: CGFloat { 1.0 - boundingBox.midY }
    }

    /// Perform OCR and return lines with size/position metadata
    func recognizeTextWithMetadata(in image: UIImage) async throws -> [RecognizedLine] {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { observation -> RecognizedLine? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return RecognizedLine(
                        text: candidate.string,
                        confidence: candidate.confidence,
                        boundingBox: observation.boundingBox,
                        height: observation.boundingBox.height
                    )
                }
                continuation.resume(returning: lines)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            // Use revision 3 for best accuracy on iOS 17+
            if #available(iOS 17.0, *) {
                request.revision = VNRecognizeTextRequestRevision3
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Simple text-only recognition (backward compat)
    func recognizeText(in image: UIImage) async throws -> [String] {
        let lines = try await recognizeTextWithMetadata(in: image)
        return lines.map { $0.text }
    }

    // MARK: - Smart Title Page Parsing

    /// Analyze OCR results using text size, position, and content heuristics
    func parseTitlePageSmart(lines: [RecognizedLine]) -> TitlePageInfo {
        // Filter noise: very short strings, low confidence, numbers-only
        let cleaned = lines.filter { line in
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count >= 2
                && line.confidence > 0.3
                && !trimmed.allSatisfy({ $0.isNumber || $0.isPunctuation || $0.isWhitespace })
                && !isNoiseText(trimmed)
        }

        guard !cleaned.isEmpty else {
            let raw = lines.map { $0.text }.joined(separator: "\n")
            return TitlePageInfo(title: nil, author: nil, rawText: raw, searchQueries: [])
        }

        // Sort by text height (largest first) — biggest text is usually the title
        let bySize = cleaned.sorted { $0.height > $1.height }

        // The median text height helps us distinguish "large" from "normal" text
        let heights = cleaned.map { $0.height }.sorted()
        let medianHeight = heights[heights.count / 2]

        // Large text = significantly bigger than median (likely title)
        let largeLines = cleaned.filter { $0.height > medianHeight * 1.3 }
            .sorted { $0.verticalPosition < $1.verticalPosition } // top to bottom

        // Find title: largest text, preferring upper portion of page
        var title: String?
        var titleLines: [String] = []

        if !largeLines.isEmpty {
            // Use all large text lines as potential title parts
            titleLines = largeLines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            title = titleLines.joined(separator: " ")
        } else {
            // No clearly large text — use the first substantial line
            if let first = cleaned.first(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 }) {
                title = first.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Find author
        var author: String?

        for line in cleaned {
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip lines we already used as title
            if titleLines.contains(trimmed) { continue }

            // Explicit "by" indicator
            if trimmed.lowercased().hasPrefix("by ") {
                author = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }

            // "Written by", "Author:", etc.
            let authorPrefixes = ["written by ", "author: ", "author ", "a novel by ", "a memoir by "]
            if let prefix = authorPrefixes.first(where: { trimmed.lowercased().hasPrefix($0) }) {
                author = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        // If no explicit author indicator, look for name-like text below the title
        if author == nil {
            let titleBottom = largeLines.last?.verticalPosition ?? 0.3
            let candidateAuthors = cleaned.filter { line in
                let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return line.verticalPosition > titleBottom
                    && !titleLines.contains(trimmed)
                    && looksLikeName(trimmed)
                    && line.height <= medianHeight * 1.3
            }
            author = candidateAuthors.first?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Build multiple search queries to try (most specific to broadest)
        var queries: [String] = []

        if let t = title, let a = author {
            queries.append("\(t) \(a)")
            queries.append(t)
        } else if let t = title {
            queries.append(t)
        } else if let a = author {
            queries.append(a)
        }

        // Also try the top 3 largest text blocks as a raw query
        let topText = bySize.prefix(3).map { $0.text }.joined(separator: " ")
        if !topText.isEmpty && !queries.contains(topText) {
            queries.append(topText)
        }

        // Finally, all text as a fallback
        let allText = cleaned.map { $0.text }.joined(separator: " ")
        if !queries.contains(allText) {
            queries.append(allText)
        }

        let rawText = cleaned.map { $0.text }.joined(separator: "\n")

        print("[OCR] Extracted title: \(title ?? "none")")
        print("[OCR] Extracted author: \(author ?? "none")")
        print("[OCR] Search queries to try: \(queries)")

        return TitlePageInfo(
            title: title,
            author: author,
            rawText: rawText,
            searchQueries: queries
        )
    }

    /// Overload for plain string arrays (backward compat)
    func parseTitlePage(lines: [String]) -> TitlePageInfo {
        let recognized = lines.enumerated().map { index, text in
            RecognizedLine(
                text: text,
                confidence: 1.0,
                boundingBox: CGRect(x: 0, y: 1.0 - Double(index) * 0.05, width: 1, height: 0.04),
                height: 0.04
            )
        }
        return parseTitlePageSmart(lines: recognized)
    }

    // MARK: - ISBN Detection

    /// Scan text lines for ISBN patterns
    func extractISBN(from lines: [String]) -> String? {
        let fullText = lines.joined(separator: " ")

        // Try ISBN-13 (starts with 978 or 979)
        let isbn13Pattern = #"(?:ISBN[- ]?(?:13)?[: ]?\s*)?(?:97[89])[\s-]?\d{1,5}[\s-]?\d{1,7}[\s-]?\d{1,7}[\s-]?\d"#
        if let match = fullText.range(of: isbn13Pattern, options: .regularExpression) {
            let isbn = String(fullText[match]).replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            if isbn.count == 13 { return isbn }
        }

        // Try ISBN-10
        let isbn10Pattern = #"ISBN[- ]?(?:10)?[: ]?\s*\d{1,5}[- ]?\d{1,7}[- ]?\d{1,7}[- ]?[\dXx]"#
        if let match = fullText.range(of: isbn10Pattern, options: [.regularExpression, .caseInsensitive]) {
            let isbn = String(fullText[match])
                .replacingOccurrences(of: "[^0-9Xx]", with: "", options: .regularExpression)
                .uppercased()
            if isbn.count == 10 { return isbn }
        }

        return nil
    }

    // MARK: - Helpers

    private func looksLikeName(_ text: String) -> Bool {
        let words = text.split(separator: " ").map(String.init)
        guard (2...5).contains(words.count) else { return false }

        let capitalizedWords = words.filter { word in
            guard let first = word.first else { return false }
            return first.isUppercase
        }

        let ratio = Double(capitalizedWords.count) / Double(words.count)
        guard ratio >= 0.6 else { return false }

        // Should not contain common non-name words
        let nonNameWords: Set<String> = [
            "the", "and", "for", "with", "from", "edition", "volume",
            "revised", "updated", "introduction", "foreword", "press",
            "publishing", "books", "chapter", "part", "new", "york"
        ]
        let lowerWords = Set(words.map { $0.lowercased() })
        let overlapCount = lowerWords.intersection(nonNameWords).count
        return overlapCount <= 1
    }

    private func isNoiseText(_ text: String) -> Bool {
        let lower = text.lowercased()
        let noisePatterns = [
            "copyright", "©", "all rights reserved", "printed in",
            "library of congress", "cataloging", "isbn", "edition",
            "first published", "published by", "printing",
            "cover design", "jacket design", "cover art",
            "manufactured", "typeset", "www.", "http",
            ".com", ".org", ".net"
        ]
        return noisePatterns.contains(where: { lower.contains($0) })
    }
}

// MARK: - Models

struct TitlePageInfo {
    let title: String?
    let author: String?
    let rawText: String
    let searchQueries: [String]   // multiple queries to try, most specific first

    var hasUsableInfo: Bool {
        title != nil || author != nil
    }

    var searchQuery: String {
        [title, author].compactMap { $0 }.joined(separator: " ")
    }
}

enum OCRError: LocalizedError {
    case invalidImage
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Could not process the image"
        case .recognitionFailed: return "Text recognition failed"
        }
    }
}
