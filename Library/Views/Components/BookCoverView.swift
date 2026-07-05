import SwiftUI

/// Displays a book's cover image with fallback to a generated placeholder
struct BookCoverView: View {
    let book: Book
    var width: CGFloat = 120
    var height: CGFloat = 180

    var body: some View {
        Group {
            if let imageData = book.coverImageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let urlString = book.coverImageURL,
                      let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholderCover
                    case .empty:
                        ProgressView()
                            .frame(width: width, height: height)
                    @unknown default:
                        placeholderCover
                    }
                }
            } else {
                placeholderCover
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.3), radius: 4, x: 2, y: 2)
    }

    /// Generated placeholder cover when no image is available
    private var placeholderCover: some View {
        ZStack {
            // Dynamic background color based on title hash
            LinearGradient(
                colors: gradientColors(for: book.title),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 8) {
                Text(book.title)
                    .font(.system(size: 12, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .foregroundStyle(.white)
                    .shadow(radius: 1)

                Text(book.authors)
                    .font(.system(size: 9, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(8)
        }
        .frame(width: width, height: height)
    }

    private func gradientColors(for title: String) -> [Color] {
        let hash = abs(title.hashValue)
        let palettes: [[Color]] = [
            [Color(red: 0.2, green: 0.3, blue: 0.5), Color(red: 0.1, green: 0.15, blue: 0.3)],
            [Color(red: 0.5, green: 0.2, blue: 0.2), Color(red: 0.3, green: 0.1, blue: 0.1)],
            [Color(red: 0.2, green: 0.4, blue: 0.3), Color(red: 0.1, green: 0.25, blue: 0.15)],
            [Color(red: 0.4, green: 0.3, blue: 0.5), Color(red: 0.2, green: 0.15, blue: 0.3)],
            [Color(red: 0.45, green: 0.35, blue: 0.2), Color(red: 0.3, green: 0.2, blue: 0.1)],
            [Color(red: 0.3, green: 0.3, blue: 0.3), Color(red: 0.15, green: 0.15, blue: 0.15)],
        ]
        return palettes[hash % palettes.count]
    }
}

/// Small price badge overlay for grid items
struct PriceBadgeView: View {
    let price: Double?
    let currency: String

    var body: some View {
        if let price = price {
            Text(formattedPrice(price, currency: currency))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.85))
                .clipShape(Capsule())
        }
    }

    private func formattedPrice(_ value: Double, currency: String) -> String {
        value.formattedAsPrice(currency: currency)
    }
}
