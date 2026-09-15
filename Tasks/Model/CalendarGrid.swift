import Foundation

enum CalendarMode: String, CaseIterable, Identifiable {
    case month, week

    var id: Self { self }

    var title: String {
        switch self {
        case .month: "Month"
        case .week: "Week"
        }
    }
}

/// Date math behind the calendar views, kept free of SwiftUI so it can be tested.
enum CalendarGrid {
    /// Always 42 days (six weeks) so the month grid keeps a stable height.
    static func monthDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        return days(from: startOfWeek(containing: month.start, calendar: calendar), count: 42, calendar: calendar)
    }

    static func weekDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        days(from: startOfWeek(containing: date, calendar: calendar), count: 7, calendar: calendar)
    }

    /// Short weekday names, starting on the calendar's first weekday.
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.shortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    /// Dated tasks keyed by the start of their due day, each day in display order.
    static func tasksByDay(_ tasks: [TaskItem], calendar: Calendar = .current) -> [Date: [TaskItem]] {
        var result: [Date: [TaskItem]] = [:]
        for task in tasks {
            guard let due = task.due else { continue }
            result[calendar.startOfDay(for: due), default: []].append(task)
        }
        return result.mapValues { $0.sorted(by: TaskFilter.displayOrder) }
    }

    /// Moves by whole months or weeks.
    static func step(_ date: Date, mode: CalendarMode, by value: Int, calendar: Calendar = .current) -> Date {
        let component: Calendar.Component = mode == .month ? .month : .weekOfYear
        return calendar.date(byAdding: component, value: value, to: date) ?? date
    }

    private static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day) ?? day
    }

    private static func days(from start: Date, count: Int, calendar: Calendar) -> [Date] {
        (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
}
