import SwiftUI
import SwiftData
import Charts

/// Reading analytics dashboard showing stats and charts
struct ReadingStatsView: View {
    @Query private var books: [Book]

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    private var yearsWithActivity: [Int] {
        let years = Set(books.compactMap { book -> Int? in
            if let date = book.dateFinishedReading {
                return Calendar.current.component(.year, from: date)
            }
            if let date = book.dateStartedReading {
                return Calendar.current.component(.year, from: date)
            }
            return nil
        })
        let currentYear = Calendar.current.component(.year, from: Date())
        return (years.union([currentYear])).sorted().reversed()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Year picker
                    if yearsWithActivity.count > 1 {
                        Picker("Year", selection: $selectedYear) {
                            ForEach(yearsWithActivity, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }

                    // Summary cards
                    summaryCards

                    // Monthly chart
                    monthlyChart

                    Divider().padding(.horizontal)

                    // Reading speed stats
                    readingSpeedSection

                    Divider().padding(.horizontal)

                    // All-time stats
                    allTimeSection

                    Spacer(minLength: 40)
                }
                .padding(.vertical)
            }
            .navigationTitle("Reading Stats")
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            statCard(
                title: "Read",
                value: "\(booksReadThisYear)",
                subtitle: "this year",
                icon: "checkmark.circle.fill",
                color: .green
            )

            statCard(
                title: "Currently Reading",
                value: "\(currentlyReading)",
                subtitle: "in progress",
                icon: "book.fill",
                color: .blue
            )

            statCard(
                title: "Want to Read",
                value: "\(wantToRead)",
                subtitle: "in backlog",
                icon: "bookmark",
                color: .orange
            )

            statCard(
                title: "Library Total",
                value: "\(books.count)",
                subtitle: "books",
                icon: "books.vertical",
                color: .purple
            )
        }
        .padding(.horizontal)
    }

    private func statCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.title3)
                Spacer()
            }
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Monthly Chart

    private var monthlyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Books Read by Month")
                .font(.headline)
                .padding(.horizontal)

            if booksReadThisYear > 0 {
                Chart {
                    ForEach(monthlyData, id: \.month) { item in
                        BarMark(
                            x: .value("Month", item.label),
                            y: .value("Books", item.count)
                        )
                        .foregroundStyle(.green.gradient)
                        .cornerRadius(4)
                    }
                }
                .chartYAxis {
                    AxisMarks(preset: .aligned) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 200)
                .padding(.horizontal)
            } else {
                Text("No books finished in \(String(selectedYear)) yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
        }
    }

    // MARK: - Reading Speed

    private var readingSpeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reading Pace")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 8) {
                if let avgDays = averageReadingDays {
                    readingSpeedRow(label: "Average reading time", value: formatDays(avgDays))
                }
                if let fastest = fastestRead {
                    readingSpeedRow(label: "Fastest read", value: "\(fastest.title) (\(formatDays(readingDays(for: fastest) ?? 0)))")
                }
                if let longest = longestRead {
                    readingSpeedRow(label: "Longest read", value: "\(longest.title) (\(formatDays(readingDays(for: longest) ?? 0)))")
                }

                if averageReadingDays == nil {
                    Text("Mark books as \"Reading\" then \"Read\" to track reading pace")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
            }
            .padding(.horizontal)
        }
    }

    private func readingSpeedRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - All-Time

    private var allTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All Time")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 8) {
                allTimeRow(label: "Total books read", value: "\(totalBooksRead)")
                allTimeRow(label: "Total pages read", value: totalPagesRead > 0 ? "\(totalPagesRead)" : "—")

                if let topMonth = mostProductiveMonth {
                    allTimeRow(
                        label: "Best month",
                        value: "\(topMonth.label) (\(topMonth.count) book\(topMonth.count == 1 ? "" : "s"))"
                    )
                }
            }
            .padding(.horizontal)
        }
    }

    private func allTimeRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
        }
    }

    // MARK: - Data Calculations

    private var booksReadThisYear: Int {
        books.filter { book in
            guard let date = book.dateFinishedReading else { return false }
            return Calendar.current.component(.year, from: date) == selectedYear
        }.count
    }

    private var currentlyReading: Int {
        books.filter { $0.readingStatusEnum == .reading }.count
    }

    private var wantToRead: Int {
        books.filter { $0.readingStatusEnum == .wantToRead }.count
    }

    private var totalBooksRead: Int {
        books.filter { $0.readingStatusEnum == .read }.count
    }

    private var totalPagesRead: Int {
        books.filter { $0.readingStatusEnum == .read }
            .compactMap { $0.pageCount }
            .reduce(0, +)
    }

    struct MonthData {
        let month: Int
        let label: String
        let count: Int
    }

    private var monthlyData: [MonthData] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let calendar = Calendar.current

        let finishedThisYear = books.filter { book in
            guard let date = book.dateFinishedReading else { return false }
            return calendar.component(.year, from: date) == selectedYear
        }

        return (1...12).map { month in
            let count = finishedThisYear.filter { book in
                guard let date = book.dateFinishedReading else { return false }
                return calendar.component(.month, from: date) == month
            }.count

            var components = DateComponents()
            components.month = month
            let date = calendar.date(from: components) ?? Date()
            let label = formatter.string(from: date)

            return MonthData(month: month, label: label, count: count)
        }
    }

    private func readingDays(for book: Book) -> Int? {
        guard let start = book.dateStartedReading, let end = book.dateFinishedReading else { return nil }
        return max(1, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1)
    }

    private var booksWithReadingTime: [Book] {
        books.filter { readingDays(for: $0) != nil }
    }

    private var averageReadingDays: Int? {
        let times = booksWithReadingTime.compactMap { readingDays(for: $0) }
        guard !times.isEmpty else { return nil }
        return times.reduce(0, +) / times.count
    }

    private var fastestRead: Book? {
        booksWithReadingTime.min(by: { (readingDays(for: $0) ?? Int.max) < (readingDays(for: $1) ?? Int.max) })
    }

    private var longestRead: Book? {
        booksWithReadingTime.max(by: { (readingDays(for: $0) ?? 0) < (readingDays(for: $1) ?? 0) })
    }

    struct MonthLabel {
        let label: String
        let count: Int
    }

    private var mostProductiveMonth: MonthLabel? {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"

        var monthly: [String: Int] = [:]
        for book in books {
            guard let date = book.dateFinishedReading else { continue }
            let key = formatter.string(from: date)
            monthly[key, default: 0] += 1
        }

        guard let top = monthly.max(by: { $0.value < $1.value }) else { return nil }
        return MonthLabel(label: top.key, count: top.value)
    }

    private func formatDays(_ days: Int) -> String {
        if days == 1 { return "1 day" }
        return "\(days) days"
    }
}
