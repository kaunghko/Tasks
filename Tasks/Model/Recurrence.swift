import Foundation

/// How a task or event repeats. Stored in JSON as
/// `{"frequency": "weekly", "interval": 2, "weekdays": ["mon", "fri"], "until": "2026-12-19"}`.
struct Recurrence: Codable, Hashable {
    enum Frequency: String, Codable, CaseIterable, Identifiable {
        case daily, weekly, monthly, yearly

        var id: Self { self }

        var title: String {
            switch self {
            case .daily: "Daily"
            case .weekly: "Weekly"
            case .monthly: "Monthly"
            case .yearly: "Yearly"
            }
        }

        var component: Calendar.Component {
            switch self {
            case .daily: .day
            case .weekly: .weekOfYear
            case .monthly: .month
            case .yearly: .year
            }
        }

        /// "day" or "days", for "Every 2 days".
        func unit(_ count: Int) -> String {
            let singular = switch self {
            case .daily: "day"
            case .weekly: "week"
            case .monthly: "month"
            case .yearly: "year"
            }
            return count == 1 ? singular : singular + "s"
        }
    }

    /// Raw values match `Calendar`'s weekday numbers, Sunday being 1.
    enum Weekday: Int, CaseIterable, Comparable, Identifiable {
        case sun = 1, mon, tue, wed, thu, fri, sat

        var id: Self { self }

        static let names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

        var name: String { Self.names[rawValue - 1] }

        init?(name: String) {
            guard let index = Self.names.firstIndex(of: name.trimmingCharacters(in: .whitespaces).lowercased()) else {
                return nil
            }
            self.init(rawValue: index + 1)
        }

        init(of date: Date, calendar: Calendar = .current) {
            self = Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .sun
        }

        /// The weekday `days` later (or earlier, when negative).
        func adding(days: Int) -> Weekday {
            Weekday(rawValue: ((rawValue - 1 + days) % 7 + 7) % 7 + 1) ?? self
        }

        /// Days after the start of a week that begins on `firstWeekday`.
        func offset(firstWeekday: Int) -> Int {
            (rawValue - firstWeekday + 7) % 7
        }

        static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var frequency: Frequency
    /// Repeats every `interval` days, weeks, months or years. Always at least 1.
    var interval: Int {
        didSet { interval = max(interval, 1) }
    }
    /// Weekly only: the days of the week it happens on. Empty means the first occurrence's weekday.
    var weekdays: Set<Weekday>
    /// The last local day an occurrence can fall on, inclusive.
    var until: Date?

    init(frequency: Frequency, interval: Int = 1, weekdays: Set<Weekday> = [], until: Date? = nil) {
        self.frequency = frequency
        self.interval = max(interval, 1)
        self.weekdays = weekdays
        self.until = until.map { Calendar.current.startOfDay(for: $0) }
    }

    /// Safety net for rules that would otherwise run for a very long time.
    static let maxIterations = 20_000

    private enum CodingKeys: String, CodingKey {
        case frequency, interval, weekdays, until
    }

    /// Tolerant decoding: only `frequency` is needed. Unknown weekdays are dropped and an
    /// unreadable `until` means no end. An unknown frequency throws, and the entry loads without a rule.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawFrequency = try container.decode(String.self, forKey: .frequency)
        guard let frequency = Frequency(rawValue: rawFrequency.trimmingCharacters(in: .whitespaces).lowercased()) else {
            throw DecodingError.dataCorruptedError(
                forKey: .frequency, in: container, debugDescription: "Unknown frequency \(rawFrequency)"
            )
        }
        let names = (try? container.decodeIfPresent([String].self, forKey: .weekdays)) ?? []
        self.init(
            frequency: frequency,
            interval: (try? container.decodeIfPresent(Int.self, forKey: .interval)) ?? 1,
            weekdays: frequency == .weekly ? Set(names.compactMap(Weekday.init(name:))) : [],
            until: (try? container.decodeIfPresent(String.self, forKey: .until)).flatMap(TaskDates.parse)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frequency, forKey: .frequency)
        if interval != 1 {
            try container.encode(interval, forKey: .interval)
        }
        if frequency == .weekly, !weekdays.isEmpty {
            try container.encode(weekdays.sorted().map(\.name), forKey: .weekdays)
        }
        try container.encodeIfPresent(until.map(TaskDates.dayString), forKey: .until)
    }

    /// Calls `body` with each occurrence in order, starting with `anchor` itself, until it returns
    /// false or the rule ends. Occurrences keep the anchor's time of day.
    ///
    /// Each one is counted from the anchor rather than from the previous occurrence, so a monthly
    /// rule on the 31st comes back to the 31st after a shorter month.
    func forEachOccurrence(from anchor: Date, calendar: Calendar = .current, _ body: (Date) -> Bool) {
        let lastDay = until.map { calendar.startOfDay(for: $0) }
        func isPastEnd(_ date: Date) -> Bool {
            lastDay.map { calendar.startOfDay(for: date) > $0 } ?? false
        }
        guard !isPastEnd(anchor), body(anchor) else { return }

        if frequency == .weekly, !weekdays.isEmpty {
            let time = calendar.dateComponents([.hour, .minute, .second], from: anchor)
            let offsets = weekdays.map { $0.offset(firstWeekday: calendar.firstWeekday) }.sorted()
            let weekStart = CalendarGrid.startOfWeek(containing: anchor, calendar: calendar)
            for week in 0..<Self.maxIterations {
                for offset in offsets {
                    guard let day = calendar.date(byAdding: .day, value: week * 7 * interval + offset, to: weekStart),
                          let date = calendar.date(
                            bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day
                          )
                    else { return }
                    guard date > anchor else { continue }
                    guard !isPastEnd(date), body(date) else { return }
                }
            }
            return
        }

        for step in 1..<Self.maxIterations {
            guard let date = calendar.date(byAdding: frequency.component, value: step * interval, to: anchor),
                  !isPastEnd(date), body(date)
            else { return }
        }
    }

    /// The first occurrence after `date` that is also on or after `earliest`, or nil once the rule has ended.
    func next(after date: Date, notBefore earliest: Date? = nil, anchor: Date, calendar: Calendar = .current) -> Date? {
        var result: Date?
        forEachOccurrence(from: anchor, calendar: calendar) { occurrence in
            if occurrence > date, earliest.map({ occurrence >= $0 }) ?? true {
                result = occurrence
                return false
            }
            return true
        }
        return result
    }

    /// Weekdays move along when the series moves by whole days.
    func shifted(byDays days: Int) -> Recurrence {
        var copy = self
        copy.weekdays = Set(weekdays.map { $0.adding(days: days) })
        return copy
    }

    /// "Every 2 weeks on Mon, Fri until Dec 19, 2026".
    var summary: String {
        var text = interval == 1 ? frequency.title : "Every \(interval) \(frequency.unit(interval))"
        if frequency == .weekly, !weekdays.isEmpty {
            let calendar = Calendar.current
            let symbols = calendar.shortWeekdaySymbols
            let names = weekdays
                .sorted { $0.offset(firstWeekday: calendar.firstWeekday) < $1.offset(firstWeekday: calendar.firstWeekday) }
                .map { symbols[$0.rawValue - 1] }
            text += " on \(names.formatted(.list(type: .and, width: .short)))"
        }
        if let until {
            text += " until \(until.formatted(.dateTime.month(.abbreviated).day().year()))"
        }
        return text
    }
}
