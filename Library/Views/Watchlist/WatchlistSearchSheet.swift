import SwiftUI

/// A search sheet that lets the user find a book by title/author/ISBN and add it to the watchlist.
struct WatchlistSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lookupService = BookLookupService()
    @State private var titleText = ""
    @State private var authorText = ""

    let onSelect: (BookSearchResult) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search fields
                Form {
                    Section {
                        TextField("Title", text: $titleText)
                            .autocorrectionDisabled()
                        TextField("Author (optional)", text: $authorText)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("Search by title, author, or ISBN to find a book to track.")
                    }
                }
                .frame(maxHeight: 180)

                Button {
                    Task {
                        await lookupService.searchByText(
                            title: titleText.isEmpty ? nil : titleText,
                            author: authorText.isEmpty ? nil : authorText
                        )
                    }
                } label: {
                    if lookupService.isSearching {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Search")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom, 12)
                .disabled(titleText.isEmpty || lookupService.isSearching)

                Divider()

                // Results
                if let error = lookupService.errorMessage {
                    ContentUnavailableView("No Results", systemImage: "magnifyingglass", description: Text(error))
                } else if lookupService.searchResults.isEmpty && !lookupService.isSearching {
                    ContentUnavailableView("Search for a Book", systemImage: "magnifyingglass", description: Text("Enter a title above to find books to add to your watchlist."))
                } else {
                    List(lookupService.searchResults, id: \.title) { result in
                        Button {
                            onSelect(result)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: result.coverImageURL.flatMap(URL.init)) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.2))
                                }
                                .frame(width: 35, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(result.authors)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    if let year = result.publishedDate?.prefix(4) {
                                        Text(year)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Watchlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
