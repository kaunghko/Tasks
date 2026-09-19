import Foundation

/// A task, or an event when it has a `start` time.
struct TaskItem: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var notes: String
    var subtasks: [Subtask]
    /// Checking off a repeating task moves it to its next occurrence instead; see `rollForward`.
    var done: Bool {
        didSet {
            if done, !oldValue {
                rollForward()
            }
        }
    }
    /// Start of the local day the task is due. Stored in JSON as `yyyy-MM-dd`.
    /// For an event, the day it starts, kept in step with `start` and not written to JSON.
    var due: Date? {
        didSet {
            if due == nil {
                dueTime = nil
            }
        }
    }
    /// A task's optional time of day on its due day. With it, `due` is written as a local timestamp
    /// such as `2026-09-22T08:00:00+09:00`. Always nil for events and tasks without a due day.
    var dueTime: TimeOfDay?
    /// Set only for events, and always together with `end`. Events are never done.
    var start: Date? {
        didSet {
            if let start {
                due = Calendar.current.startOfDay(for: start)
                dueTime = nil
                done = false
            }
        }
    }
    var end: Date?
    /// For a task, the rule its due date moves along when checked off. For an event, the rule its
    /// occurrences follow, counted from `start`; the calendar shows every occurrence.
    var recurrence: Recurrence?
    /// When a timed task or an event notifies. Tasks without a due time never do.
    var alert: TaskAlert
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        notes: String = "",
        subtasks: [Subtask] = [],
        done: Bool = false,
        due: Date? = nil,
        dueTime: TimeOfDay? = nil,
        start: Date? = nil,
        end: Date? = nil,
        recurrence: Recurrence? = nil,
        alert: TaskAlert = .atTime,
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
            self.dueTime = due == nil ? nil : dueTime
        }
        self.recurrence = recurrence
        self.alert = alert
        self.createdAt = TaskDates.wholeSeconds(createdAt)
    }

    static let defaultEventDuration: TimeInterval = 3600

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, subtasks, done, due, start, end, recurrence = "repeat", alert, createdAt
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
        // A `due` with a time, such as `2026-09-22T08:00:00+09:00`, keeps its local time of day.
        let dueTime = (try? container.decodeIfPresent(String.self, forKey: .due))
            .flatMap { TaskDates.hasTime($0) ? TaskDates.parse($0) : nil }
            .map { TimeOfDay(of: $0) }
        self.init(
            id: (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID(),
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
            notes: checklist.notes,
            subtasks: (try container.decodeIfPresent([Subtask].self, forKey: .subtasks) ?? []) + checklist.subtasks,
            done: try container.decodeIfPresent(Bool.self, forKey: .done) ?? false,
            due: date(.due),
            dueTime: dueTime,
            start: date(.start),
            end: date(.end),
            // A rule that can't be read is dropped rather than failing the whole file.
            recurrence: (try? container.decodeIfPresent(Recurrence.self, forKey: .recurrence)) ?? nil,
            alert: (try? container.decodeIfPresent(TaskAlert.self, forKey: .alert)) ?? .atTime,
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
            if let due, let dueTime, let timed = dueTime.on(due) {
                try container.encode(TaskDates.localTimestampString(timed), forKey: .due)
            } else {
                try container.encodeIfPresent(due.map(TaskDates.dayString), forKey: .due)
            }
        }
        try container.encodeIfPresent(recurrence, forKey: .recurrence)
        // Left out at the default, so files without alerts save unchanged.
        if alert != .atTime {
            try container.encode(alert, forKey: .alert)
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

    /// A task's due time, such as "08:00".
    var dueTimeLabel: String? {
        guard let due, let date = dueTime?.on(due) else { return nil }
        return date.formatted(.dateTime.hour().minute())
    }

    /// When an event starts or a timed task is due, for ordering items within a day.
    var scheduledTime: Date? {
        start ?? due.flatMap { dueTime?.on($0) }
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
        guard let range = timeRangeLabel ?? dueTimeLabel else { return dueLabel }
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
        set {
            due = newValue ? (due ?? Calendar.current.startOfDay(for: .now)) : nil
            if !newValue {
                recurrence = nil
            }
        }
    }

    var dueDay: Date {
        get { due ?? Calendar.current.startOfDay(for: .now) }
        set { due = Calendar.current.startOfDay(for: newValue) }
    }

    /// Turning a time on starts at the next whole hour.
    var hasDueTime: Bool {
        get { dueTime != nil }
        set {
            guard newValue else {
                dueTime = nil
                return
            }
            guard dueTime == nil else { return }
            if due == nil {
                due = Calendar.current.startOfDay(for: .now)
            }
            let hour = Calendar.current.component(.hour, from: TaskItem.defaultEventStart(on: due ?? .now))
            dueTime = TimeOfDay(hour: hour)
        }
    }

    /// The due time as a date on the due day, for a time picker.
    var dueTimeDate: Date {
        get { due.flatMap { dueTime?.on($0) } ?? dueDay }
        set { dueTime = TimeOfDay(of: newValue) }
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
        } else if let timed = dueTime?.on(day, calendar: calendar) {
            start = timed
            end = start.addingTimeInterval(TaskItem.defaultEventDuration)
        } else {
            start = TaskItem.defaultEventStart(on: day, now: now, calendar: calendar)
            end = start.addingTimeInterval(TaskItem.defaultEventDuration)
        }
        self.start = TaskDates.wholeSeconds(start)
        self.end = TaskDates.wholeSeconds(end)
        move(toDay: day, calendar: calendar)
    }

    /// Turns an event back into a task due on the day and at the time it started, so it keeps its place on the calendar.
    mutating func makeTask(done: Bool = false, calendar: Calendar = .current) {
        guard let start else { return }
        dueTime = TimeOfDay(of: start, calendar: calendar)
        self.start = nil
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

    /// Moves an event to a new start, keeping its length, or makes a task due at that day and time.
    mutating func move(toTime date: Date, calendar: Calendar = .current) {
        guard !isEvent else {
            move(toStart: date)
            return
        }
        due = calendar.startOfDay(for: date)
        dueTime = TimeOfDay(of: date, calendar: calendar)
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

// MARK: - Repeating

extension TaskItem {
    /// A checked-off repeating task becomes due on its next occurrence that isn't in the past, and
    /// opens again with its subtasks unchecked. Once the rule has ended, it stays done.
    mutating func rollForward(now: Date = .now, calendar: Calendar = .current) {
        guard done, !isEvent, let recurrence, let due else { return }
        let today = calendar.startOfDay(for: now)
        guard let next = recurrence.next(after: due, notBefore: today, anchor: due, calendar: calendar) else { return }
        self.due = calendar.startOfDay(for: next)
        done = false
        for index in subtasks.indices {
            subtasks[index].done = false
        }
    }

    /// Copies of a repeating event moved to each occurrence that overlaps `range`, sharing its id.
    /// Anything else is itself, when it's in the range at all.
    func occurrences(in range: DateInterval, calendar: Calendar = .current) -> [TaskItem] {
        guard let start, let end, let recurrence else { return [self] }
        let duration = end.timeIntervalSince(start)
        var result: [TaskItem] = []
        recurrence.forEachOccurrence(from: start, calendar: calendar) { occurrence in
            guard occurrence < range.end else { return false }
            if occurrence.addingTimeInterval(duration) > range.start {
                result.append(moved(to: occurrence, duration: duration))
            }
            return true
        }
        return result
    }

    /// The occurrence of a repeating event that lists show: the first one that hasn't ended,
    /// or the last one once the rule is over. Anything else is itself.
    func currentOccurrence(now: Date = .now, calendar: Calendar = .current) -> TaskItem {
        guard let start, let end, let recurrence else { return self }
        let duration = end.timeIntervalSince(start)
        var current = start
        recurrence.forEachOccurrence(from: start, calendar: calendar) { occurrence in
            current = occurrence
            return occurrence.addingTimeInterval(duration) <= now
        }
        return current == start ? self : moved(to: current, duration: duration)
    }

    private func moved(to occurrence: Date, duration: TimeInterval) -> TaskItem {
        var copy = self
        copy.start = occurrence
        copy.end = occurrence.addingTimeInterval(duration)
        return copy
    }

    var isRepeatingEvent: Bool { isEvent && recurrence != nil }

    /// Moves a whole event series so its stored start lands on `newStart`, keeping its length.
    /// Weekdays shift by as many days as the start did.
    mutating func moveSeries(toStart newStart: Date, calendar: Calendar = .current) {
        guard let start else { return }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: newStart)
        ).day ?? 0
        recurrence = recurrence?.shifted(byDays: days)
        move(toStart: newStart)
    }

    /// Moves a whole event series by whole days, keeping its time of day.
    mutating func moveSeries(byDays days: Int, calendar: Calendar = .current) {
        guard let start, days != 0, let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: start)) else {
            return
        }
        recurrence = recurrence?.shifted(byDays: days)
        move(toDay: day, calendar: calendar)
    }

    /// The day occurrences are counted from: an event's start, or a task's due day.
    private var recurrenceAnchor: Date {
        start ?? due ?? Calendar.current.startOfDay(for: .now)
    }

    /// Picking a rule for a task without a due date makes it due today.
    var repeatFrequency: Recurrence.Frequency? {
        get { recurrence?.frequency }
        set {
            guard let newValue else {
                recurrence = nil
                return
            }
            guard newValue != recurrence?.frequency else { return }
            var rule = recurrence ?? Recurrence(frequency: newValue)
            rule.frequency = newValue
            if newValue != .weekly {
                rule.weekdays = []
            }
            if !isEvent, due == nil {
                due = Calendar.current.startOfDay(for: .now)
            }
            recurrence = rule
        }
    }

    var repeatInterval: Int {
        get { recurrence?.interval ?? 1 }
        set { recurrence?.interval = newValue }
    }

    /// The weekdays a weekly rule shows as picked: its own, or the anchor's when it has none.
    /// Picking days that leave out the current day moves the item to the next picked day.
    var repeatWeekdays: Set<Recurrence.Weekday> {
        get {
            guard let recurrence else { return [] }
            return recurrence.weekdays.isEmpty ? [Recurrence.Weekday(of: recurrenceAnchor)] : recurrence.weekdays
        }
        set {
            guard !newValue.isEmpty, recurrence != nil else { return }
            moveToFirstDay(in: newValue)
            recurrence?.weekdays = newValue
        }
    }

    /// Moves the item forward to the nearest of `weekdays`, unless it's already on one.
    private mutating func moveToFirstDay(in weekdays: Set<Recurrence.Weekday>, calendar: Calendar = .current) {
        let anchorDay = calendar.startOfDay(for: recurrenceAnchor)
        let current = Recurrence.Weekday(of: anchorDay, calendar: calendar)
        if !weekdays.isEmpty, !weekdays.contains(current),
           let days = (1..<7).first(where: { weekdays.contains(current.adding(days: $0)) }),
           let day = calendar.date(byAdding: .day, value: days, to: anchorDay) {
            move(toDay: day, calendar: calendar)
        }
    }

    var hasRepeatEnd: Bool {
        get { recurrence?.until != nil }
        set {
            let calendar = Calendar.current
            let defaultEnd = calendar.date(byAdding: .month, value: 1, to: calendar.startOfDay(for: recurrenceAnchor))
            let until = newValue ? (recurrence?.until ?? defaultEnd) : nil
            recurrence?.until = until
        }
    }

    var repeatUntil: Date {
        get { recurrence?.until ?? Calendar.current.startOfDay(for: recurrenceAnchor) }
        set { recurrence?.until = Calendar.current.startOfDay(for: newValue) }
    }
}

// MARK: - Natural language

extension TaskItem {
    /// Applies what `ScheduleParser` found in the title, as one change. It never switches kinds:
    /// a time moves an event, or becomes a task's due time (due today if it had no day). A day alone
    /// reschedules the item, keeping its time, and a weekly rule on chosen days moves it to the nearest of them.
    mutating func apply(_ detected: DetectedSchedule, now: Date = .now, calendar: Calendar = .current) {
        title = detected.title
        let today = calendar.startOfDay(for: now)

        if let time = detected.start, let start {
            let day = detected.day ?? calendar.startOfDay(for: start)
            guard let newStart = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) else {
                return
            }
            let newEnd: Date
            if let endTime = detected.end,
               let sameDay = calendar.date(bySettingHour: endTime.hour, minute: endTime.minute, second: 0, of: day) {
                newEnd = sameDay > newStart ? sameDay : calendar.date(byAdding: .day, value: 1, to: sameDay) ?? sameDay
            } else if let duration = detected.duration {
                newEnd = newStart.addingTimeInterval(duration)
            } else if let end {
                newEnd = newStart.addingTimeInterval(end.timeIntervalSince(start))
            } else {
                newEnd = newStart.addingTimeInterval(TaskItem.defaultEventDuration)
            }
            self.start = TaskDates.wholeSeconds(newStart)
            end = TaskDates.wholeSeconds(newEnd)
        } else if let time = detected.start {
            due = detected.day ?? due ?? today
            dueTime = time
        } else if let day = detected.day {
            move(toDay: day, calendar: calendar)
        } else if detected.recurrence != nil, !isEvent, due == nil {
            due = today
        }

        if let rule = detected.recurrence {
            if rule.frequency == .weekly {
                moveToFirstDay(in: rule.weekdays, calendar: calendar)
            }
            recurrence = rule
        }
        if let alert = detected.alert {
            self.alert = alert
        }
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

    /// Whether a date string has a time part, like `2026-09-22T08:00:00+09:00`, rather than a plain day.
    static func hasTime(_ string: String) -> Bool {
        string.contains("T")
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
