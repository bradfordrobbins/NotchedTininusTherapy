import SwiftUI

struct ListeningUsageView: View {
    @Environment(ListeningLog.self) private var log
    @State private var visibleMonth = Date()

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                monthHeader
                weekdayHeader
                monthGrid
                summary
                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle("Listening")
            .helpSheet()
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                visibleMonth = calendar.date(byAdding: .month, value: -1, to: visibleMonth) ?? visibleMonth
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(monthTitle)
                .font(.title2.weight(.semibold))
            Spacer()
            Button {
                visibleMonth = calendar.date(byAdding: .month, value: 1, to: visibleMonth) ?? visibleMonth
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .buttonStyle(.borderless)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let days = daysInVisibleMonth()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 58)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let minutes = log.minutes(on: date)
        let isToday = calendar.isDateInToday(date)
        return VStack(spacing: 4) {
            Text("\(calendar.component(.day, from: date))")
                .font(.caption)
                .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
            Text(minutes > 0 ? String(format: "%d", minutes) : " ")
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(minutes > 0 ? Color.primary : Color.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(cellBackground(minutes: minutes, isToday: isToday), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today \(log.minutes(on: .now)) min")
                .font(.headline)
            Text("This month \(log.minutesInMonth(containing: visibleMonth)) min")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Minutes of notched therapy music. Totals are saved on this device.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var monthTitle: String {
        visibleMonth.formatted(.dateTime.month(.wide).year())
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...]) + Array(symbols[..<start])
    }

    private func daysInVisibleMonth() -> [Date?] {
        guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonth)),
              let range = calendar.range(of: .day, in: .month, for: start) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            days.append(calendar.date(byAdding: .day, value: day - 1, to: start))
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }

    private func cellBackground(minutes: Int, isToday: Bool) -> Color {
        if minutes >= 60 {
            return Color.accentColor.opacity(0.28)
        }
        if minutes >= 30 {
            return Color.accentColor.opacity(0.16)
        }
        if minutes > 0 {
            return Color.accentColor.opacity(0.08)
        }
        return isToday ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.04)
    }
}
