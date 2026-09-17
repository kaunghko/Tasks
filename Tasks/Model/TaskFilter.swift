import Foundation

enum TaskFilter: String, CaseIterable, Identifiable, Hashable {
    case all, today, upcoming, completed

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .completed: "Completed"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "tray.full"
        case .today: "sun.max"
        case .upcoming: "calendar.badge.clock"
        case .completed: "checkmark.circle"
        }
    }

    /// `today` includes overdue tasks, so nothing slips out of view, and events that haven't ended yet.
    /// A repeating event counts as its current occurrence.
    func includes(_ task: TaskItem, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let task = task.currentOccurrence(now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        if let start = task.start, let end = task.end {
            switch self {
            case .all:
                return true
            case .today:
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
                return start < tomorrow && end > now
            case .upcoming:
                return calendar.startOfDay(for: start) > today
            case .completed:
                return false
            }
        }
        switch self {
        case .all:
            return true
        case .today:
            guard !task.done, let due = task.due else { return false }
            return calendar.startOfDay(for: due) <= today
        case .upcoming:
            guard !task.done, let due = task.due else { return false }
            return calendar.startOfDay(for: due) > today
        case .completed:
            return task.done
        }
    }

    /// The most specific list a task shows up in: Completed, Today (with overdue), Upcoming,
    /// or All for open tasks without a due date and events that are over.
    static func home(for task: TaskItem, now: Date = .now, calendar: Calendar = .current) -> TaskFilter {
        [.completed, .today, .upcoming].first { $0.includes(task, now: now, calendar: calendar) } ?? .all
    }

    /// Filters, searches (title and notes) and sorts tasks for display.
    /// Repeating events come back as their current occurrence.
    func apply(
        to tasks: [TaskItem],
        search: String = "",
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [TaskItem] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return tasks
            .map { $0.currentOccurrence(now: now, calendar: calendar) }
            .filter { includes($0, now: now, calendar: calendar) }
            .filter { query.isEmpty
                || $0.title.localizedStandardContains(query)
                || $0.notes.localizedStandardContains(query) }
            .sorted { TaskFilter.displayOrder($0, $1, now: now) }
    }

    /// Open tasks first, then by due date (undated last), then oldest first.
    /// Events count as done once they end, and come before tasks on the same day, by start time.
    static func displayOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        displayOrder(a, b, now: .now)
    }

    static func displayOrder(_ a: TaskItem, _ b: TaskItem, now: Date) -> Bool {
        let aFinished = a.isFinished(now: now), bFinished = b.isFinished(now: now)
        if aFinished != bFinished {
            return !aFinished
        }
        switch (a.due, b.due) {
        case let (lhs?, rhs?) where lhs != rhs:
            return lhs < rhs
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            return sameDayOrder(a, b)
        }
    }

    /// Events by start time, then tasks oldest first.
    static func sameDayOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        switch (a.scheduledTime, b.scheduledTime) {
        case let (lhs?, rhs?) where lhs != rhs:
            return lhs < rhs
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            return a.createdAt < b.createdAt
        }
    }
}
