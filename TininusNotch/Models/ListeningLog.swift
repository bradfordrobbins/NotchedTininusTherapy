import Foundation

@Observable
@MainActor
final class ListeningLog {
    private enum Keys {
        static let secondsByDay = "listeningSecondsByDay"
    }

    private let defaults: UserDefaults
    private var secondsByDay: [String: Double]
    private var unsavedSeconds: Double = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.dictionary(forKey: Keys.secondsByDay) as? [String: Double] {
            secondsByDay = stored
        } else {
            secondsByDay = [:]
        }
    }

    func add(seconds: TimeInterval, on date: Date = .now) {
        guard seconds.isFinite, seconds > 0, seconds < 30 else { return }
        let key = Self.dayKey(date)
        secondsByDay[key, default: 0] += seconds
        unsavedSeconds += seconds
        if unsavedSeconds >= 1 {
            persist()
        }
    }

    func flush() {
        persist()
    }

    func minutes(on date: Date) -> Int {
        let seconds = secondsByDay[Self.dayKey(date)] ?? 0
        return min(999, Int(seconds / 60.0))
    }

    func minutesInMonth(containing date: Date) -> Int {
        let calendar = Calendar.current
        let total = secondsByDay.reduce(0.0) { partial, item in
            guard let day = Self.date(fromDayKey: item.key),
                  calendar.isDate(day, equalTo: date, toGranularity: .month) else {
                return partial
            }
            return partial + item.value
        }
        return Int(total / 60.0)
    }

    static func dayKey(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private func persist() {
        defaults.set(secondsByDay, forKey: Keys.secondsByDay)
        unsavedSeconds = 0
    }
}
