import Foundation

struct TaskItem: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var notes: String
    var done: Bool
    /// Start of the local day the task is due. Stored in JSON as `yyyy-MM-dd`.
    var due: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        notes: String = "",
        done: Bool = false,
        due: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.done = done
        self.due = due.map { Calendar.current.startOfDay(for: $0) }
        // JSON timestamps have whole-second precision; match it so values round-trip.
        self.createdAt = Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down))
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, done, due, createdAt
    }

    /// Tolerant decoding: only `title` is really expected, everything else has a default,
    /// so hand-written entries like `{"title": "Buy milk"}` load fine.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID(),
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
            notes: try container.decodeIfPresent(String.self, forKey: .notes) ?? "",
            done: try container.decodeIfPresent(Bool.self, forKey: .done) ?? false,
            due: (try? container.decodeIfPresent(String.self, forKey: .due)).flatMap(TaskDates.parse),
            createdAt: (try? container.decodeIfPresent(String.self, forKey: .createdAt))
                .flatMap(TaskDates.parse) ?? .now
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(done, forKey: .done)
        try container.encodeIfPresent(due.map(TaskDates.dayString), forKey: .due)
        try container.encode(TaskDates.timestampString(createdAt), forKey: .createdAt)
    }

    func isOverdue(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !done, let due else { return false }
        return calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
    }
}

// Key-path friendly accessors so views can bind to them directly (`$task.hasDueDate`).
extension TaskItem {
    var hasDueDate: Bool {
        get { due != nil }
        set { due = newValue ? (due ?? Calendar.current.startOfDay(for: .now)) : nil }
    }

    var dueDay: Date {
        get { due ?? Calendar.current.startOfDay(for: .now) }
        set { due = Calendar.current.startOfDay(for: newValue) }
    }
}

extension Array where Element == TaskItem {
    /// Looks a task up by id, so bindings stay valid when the array is filtered,
    /// reordered or has items deleted.
    subscript(id id: TaskItem.ID) -> TaskItem {
        get { first { $0.id == id } ?? TaskItem(id: id) }
        set {
            guard let index = firstIndex(where: { $0.id == id }) else { return }
            self[index] = newValue
        }
    }
}

enum TaskDates {
    /// Accepts `2026-09-22`, `2026-09-22T09:00:00Z` or the same with fractional seconds.
    static func parse(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        let timestamp = ISO8601DateFormatter()
        if let date = timestamp.date(from: trimmed) {
            return date
        }
        timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = timestamp.date(from: trimmed) {
            return date
        }
        return dayFormatter().date(from: trimmed)
    }

    static func dayString(_ date: Date) -> String {
        dayFormatter().string(from: date)
    }

    static func timestampString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
