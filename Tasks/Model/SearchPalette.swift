import Foundation

/// Where the main window points: one of the task lists, or the calendar.
enum AppDestination: Hashable {
    case filter(TaskFilter)
    case calendar
}

/// What the ⌘K palette searches. Tab locks `tasks`; a leading `@` locks `views`.
enum PaletteScope: Hashable {
    case mixed, tasks, views

    var title: String? {
        switch self {
        case .mixed: nil
        case .tasks: "Tasks"
        case .views: "Views"
        }
    }

    /// Tab switches to tasks, or back to everything when tasks are already locked.
    var afterTab: PaletteScope {
        self == .tasks ? .mixed : .tasks
    }
}

struct PaletteQuery: Equatable {
    var scope: PaletteScope
    var term: String

    /// A leading `@` turns a mixed search into a view search; a locked scope takes the text literally.
    static func parse(_ text: String, lockedScope: PaletteScope = .mixed) -> PaletteQuery {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if lockedScope == .mixed, trimmed.hasPrefix("@") {
            return PaletteQuery(scope: .views, term: trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
        }
        return PaletteQuery(scope: lockedScope, term: trimmed)
    }
}

/// A place the palette can jump to.
struct PaletteView: Hashable, Identifiable {
    let title: String
    let subtitle: String
    let systemImage: String
    /// Extra words that also find this view, e.g. "daily" for Today.
    let aliases: [String]
    let destination: AppDestination
    /// Set for the Month and Week entries; `nil` keeps the calendar's current mode.
    var calendarMode: CalendarMode?

    var id: String { title }

    static let all: [PaletteView] = TaskFilter.allCases.map { filter in
        PaletteView(
            title: filter.title, subtitle: "List", systemImage: filter.systemImage,
            aliases: filter.aliases, destination: .filter(filter)
        )
    } + [
        PaletteView(
            title: "Calendar", subtitle: "Calendar", systemImage: "calendar",
            aliases: ["cal"], destination: .calendar
        ),
    ] + CalendarMode.allCases.map { mode in
        PaletteView(
            title: mode.title, subtitle: "Calendar", systemImage: mode.systemImage,
            aliases: mode.aliases, destination: .calendar, calendarMode: mode
        )
    }
}

enum PaletteResult: Hashable, Identifiable {
    case view(PaletteView)
    case task(TaskItem)

    var id: String {
        switch self {
        case .view(let view): "view-\(view.id)"
        case .task(let task): "task-\(task.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .view(let view): view.title
        case .task(let task): task.title.isEmpty ? "Untitled" : task.title
        }
    }
}

enum SearchPalette {
    static let maxResults = 50
    /// Open tasks due today or overdue, shown in a mixed search before anything is typed.
    static let maxSuggestions = 8

    /// Views first, then tasks. Each group is ranked by how well it matches.
    static func results(
        for query: PaletteQuery,
        tasks: [TaskItem],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [PaletteResult] {
        var results: [PaletteResult] = []
        if query.scope != .tasks {
            results += matchingViews(query.term).map(PaletteResult.view)
        }
        if query.scope != .views {
            let found: [TaskItem]
            if !query.term.isEmpty {
                found = matchingTasks(query.term, in: tasks)
            } else if query.scope == .tasks {
                found = TaskFilter.all.apply(to: tasks, now: now, calendar: calendar)
            } else {
                found = Array(TaskFilter.today.apply(to: tasks, now: now, calendar: calendar).prefix(maxSuggestions))
            }
            results += found.map(PaletteResult.task)
        }
        return Array(results.prefix(maxResults))
    }

    static func matchingViews(_ term: String) -> [PaletteView] {
        guard !term.isEmpty else { return PaletteView.all }
        return PaletteView.all.enumerated()
            .compactMap { index, view -> (rank: Int, index: Int, view: PaletteView)? in
                let ranks = ([view.title] + view.aliases).compactMap { matchRank(of: term, in: $0) }
                return ranks.min().map { ($0, index, view) }
            }
            .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
            .map(\.view)
    }

    /// Title matches rank by position; a match only in the notes comes last.
    static func matchingTasks(_ term: String, in tasks: [TaskItem]) -> [TaskItem] {
        tasks
            .compactMap { task -> (rank: Int, task: TaskItem)? in
                if let rank = matchRank(of: term, in: task.title) {
                    return (rank, task)
                }
                return task.notes.localizedStandardContains(term) ? (3, task) : nil
            }
            .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : TaskFilter.displayOrder($0.task, $1.task) }
            .map(\.task)
    }

    /// 0 when the text starts with the term, 1 when a word does, 2 when it appears anywhere.
    static func matchRank(of term: String, in text: String) -> Int? {
        guard let range = text.localizedStandardRange(of: term) else { return nil }
        if range.lowerBound == text.startIndex { return 0 }
        let startsWord = text
            .split { !$0.isLetter && !$0.isNumber }
            .contains { $0.localizedStandardRange(of: term)?.lowerBound == $0.startIndex }
        return startsWord ? 1 : 2
    }
}

private extension TaskFilter {
    var aliases: [String] {
        switch self {
        case .all: ["everything", "inbox"]
        case .today: ["day", "daily", "overdue"]
        case .upcoming: ["later", "future", "next"]
        case .completed: ["done", "finished"]
        }
    }
}

private extension CalendarMode {
    var systemImage: String {
        switch self {
        case .month: "square.grid.3x3"
        case .week: "rectangle.split.3x1"
        }
    }

    var aliases: [String] {
        switch self {
        case .month: ["monthly", "calendar"]
        case .week: ["weekly", "calendar"]
        }
    }
}
