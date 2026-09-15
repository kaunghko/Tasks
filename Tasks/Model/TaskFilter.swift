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

    /// `today` includes overdue tasks, so nothing slips out of view.
    func includes(_ task: TaskItem, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
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
    /// or All for open tasks without a due date.
    static func home(for task: TaskItem, now: Date = .now, calendar: Calendar = .current) -> TaskFilter {
        [.completed, .today, .upcoming].first { $0.includes(task, now: now, calendar: calendar) } ?? .all
    }

    /// Filters, searches (title and notes) and sorts tasks for display.
    func apply(
        to tasks: [TaskItem],
        search: String = "",
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [TaskItem] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return tasks
            .filter { includes($0, now: now, calendar: calendar) }
            .filter { query.isEmpty
                || $0.title.localizedStandardContains(query)
                || $0.notes.localizedStandardContains(query) }
            .sorted(by: TaskFilter.displayOrder)
    }

    /// Open tasks first, then by due date (undated last), then oldest first.
    static func displayOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.done != b.done {
            return !a.done
        }
        switch (a.due, b.due) {
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
