import Foundation

/// A task, or an event when it has a `start` time.
struct TaskItem: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var notes: String
    var subtasks: [Subtask]
    var done: Bool
    /// Start of the local day the task is due. Stored in JSON as `yyyy-MM-dd`.
    /// For an event, the day it starts, kept in step with `start` and not written to JSON.
    var due: Date?
    /// Set only for events, and always together with `end`. Events are never done.
    var start: Date? {
        didSet {
            if let start {
                due = Calendar.current.startOfDay(for: start)
                done = false
            }
        }
    }
    var end: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        notes: String = "",
        subtasks: [Subtask] = [],
        done: Bool = false,
        due: Date? = nil,
        start: Date? = nil,
        end: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.subtasks = subtasks
        // JSON timestamps have whole-second precision; match it so values round-trip.
        let start = start.map(TaskDates.wholeSeconds)
        if let start {
            self.start = start
            self.end = end.map(TaskDates.wholeSeconds).flatMap { $0 > start ? $0 : nil }
                ?? start.addingTimeInterval(TaskItem.defaultEventDuration)
            self.done = false
            self.due = Calendar.current.startOfDay(for: start)
        } else {
            self.start = nil
            self.end = nil
            self.done = done
            self.due = due.map { Calendar.current.startOfDay(for: $0) }
        }
        self.createdAt = TaskDates.wholeSeconds(createdAt)
    }

    static let defaultEventDuration: TimeInterval = 3600

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, subtasks, done, due, start, end, createdAt
    }

    /// Tolerant decoding: only `title` is really expected, everything else has a default,
    /// so hand-written entries like `{"title": "Buy milk"}` load fine.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `- [ ]` lines written by hand into notes become subtasks, after any listed ones.
        let checklist = Checklist.extract(from: try container.decodeIfPresent(String.self, forKey: .notes) ?? "")
        func date(_ key: CodingKeys) -> Date? {
            (try? container.decodeIfPresent(String.self, forKey: key)).flatMap(TaskDates.parse)
        }
        self.init(
            id: (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID(),
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
            notes: checklist.notes,
            subtasks: (try container.decodeIfPresent([Subtask].self, forKey: .subtasks) ?? []) + checklist.subtasks,
            done: try container.decodeIfPresent(Bool.self, forKey: .done) ?? false,
            due: date(.due),
            start: date(.start),
            end: date(.end),
            createdAt: date(.createdAt) ?? .now
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        // Left out when empty, so files without subtasks save unchanged.
        if !subtasks.isEmpty {
            try container.encode(subtasks, forKey: .subtasks)
        }
        if let start {
            // Events store their times with the local offset, which reads well when edited by hand.
            try container.encode(TaskDates.localTimestampString(start), forKey: .start)
            try container.encodeIfPresent(end.map(TaskDates.localTimestampString), forKey: .end)
        } else {
            try container.encode(done, forKey: .done)
            try container.encodeIfPresent(due.map(TaskDates.dayString), forKey: .due)
        }
        try container.encode(TaskDates.timestampString(createdAt), forKey: .createdAt)
    }

    var isEvent: Bool { start != nil }

    func isOverdue(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !isEvent, !done, let due else { return false }
        return calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
    }

    func hasEnded(now: Date = .now) -> Bool {
        guard let end else { return false }
        return end <= now
    }

    /// Done tasks and events that are over. Lists sort these last and show them dimmed.
    func isFinished(now: Date = .now) -> Bool {
        done || hasEnded(now: now)
    }

    /// "Today", "Tomorrow" or a short date such as "Sep 22".
    var dueLabel: String? {
        guard let due else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(due) { return "Today" }
        if calendar.isDateInTomorrow(due) { return "Tomorrow" }
        return due.formatted(.dateTime.month(.abbreviated).day())
    }

    /// An event's start time, such as "09:00", in the user's locale.
    var startTimeLabel: String? {
        start?.formatted(.dateTime.hour().minute())
    }

    /// "09:00–10:15", or "22:00–Sep 18, 01:00" when the event runs past its first day.
    var timeRangeLabel: String? {
        guard let start, let end else { return nil }
        let time: Date.FormatStyle = .dateTime.hour().minute()
        let endLabel = Calendar.current.isDate(start, inSameDayAs: end)
            ? end.formatted(time)
            : "\(end.formatted(.dateTime.month(.abbreviated).day())), \(end.formatted(time))"
        return "\(start.formatted(time))–\(endLabel)"
    }

    /// The day and time for lists: "09:00–10:15" today, "Tomorrow · 09:00–10:15" otherwise.
    /// Tasks just show their due day.
    var scheduleLabel: String? {
        guard let range = timeRangeLabel else { return dueLabel }
        guard let due, !Calendar.current.isDateInToday(due), let dueLabel else { return range }
        return "\(dueLabel) · \(range)"
    }

    /// Finished and total subtask counts, or nil when there are none.
    var subtaskProgress: (done: Int, total: Int)? {
        guard !subtasks.isEmpty else { return nil }
        return (subtasks.count { $0.done }, subtasks.count)
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

    /// Switches between task and event with the defaults of `makeEvent()` and `makeTask()`.
    var isEventKind: Bool {
        get { isEvent }
        set { newValue ? makeEvent() : makeTask() }
    }

    /// Turns a task into an event on its due day (or today). `previous` gives back the times
    /// it had before it last became a task, moved to the current due day; otherwise it starts
    /// at the next whole hour and lasts an hour.
    mutating func makeEvent(previous: (start: Date, end: Date)? = nil, now: Date = .now, calendar: Calendar = .current) {
        guard !isEvent else { return }
        let day = due ?? calendar.startOfDay(for: now)
        let start: Date
        let end: Date
        if let previous, previous.end > previous.start {
            start = previous.start
            end = previous.end
        } else {
            start = TaskItem.defaultEventStart(on: day, now: now, calendar: calendar)
            end = start.addingTimeInterval(TaskItem.defaultEventDuration)
        }
        self.start = TaskDates.wholeSeconds(start)
        self.end = TaskDates.wholeSeconds(end)
        move(toDay: day, calendar: calendar)
    }

    /// Turns an event back into a task due on the day it started.
    mutating func makeTask(done: Bool = false) {
        guard isEvent else { return }
        start = nil
        end = nil
        self.done = done
    }

    /// Moving the start keeps the event's length. Stable for tasks too, so a picker that is
    /// still on screen while the item switches kinds doesn't see a new value on every read.
    var eventStart: Date {
        get { start ?? due ?? Calendar.current.startOfDay(for: .now) }
        set { move(toStart: newValue) }
    }

    /// Always after the start: an end at or before it becomes a 15-minute event.
    var eventEnd: Date {
        get { end ?? eventStart.addingTimeInterval(TaskItem.defaultEventDuration) }
        set {
            guard let start else { return }
            let value = TaskDates.wholeSeconds(newValue)
            end = value > start ? value : start.addingTimeInterval(15 * 60)
        }
    }

    /// Next whole hour of the current time, placed on `day`. Late at night it stays on that day at 23:00.
    static func defaultEventStart(on day: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        let hour = min(calendar.component(.hour, from: now) + 1, 23)
        let startOfDay = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: startOfDay) ?? startOfDay
    }

    /// Reschedules to another day. An event keeps its time of day and length; a task becomes due that day.
    mutating func move(toDay day: Date, calendar: Calendar = .current) {
        guard let start else {
            due = calendar.startOfDay(for: day)
            return
        }
        let time = calendar.dateComponents([.hour, .minute, .second], from: start)
        let newStart = calendar.date(
            bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0,
            of: calendar.startOfDay(for: day)
        ) ?? start
        move(toStart: newStart)
    }

    /// Moves an event to a new start, keeping its length. Does nothing to a task.
    mutating func move(toStart newStart: Date) {
        guard let start else { return }
        let duration = (end ?? start.addingTimeInterval(TaskItem.defaultEventDuration)).timeIntervalSince(start)
        let value = TaskDates.wholeSeconds(newStart)
        self.start = value
        end = value.addingTimeInterval(duration)
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

    /// Like `timestampString`, but in the local time zone: `2026-09-22T09:00:00+09:00`.
    static func localTimestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
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
