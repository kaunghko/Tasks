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

    /// From the start of the first day to the end of the last one.
    static func interval(of days: [Date], calendar: Calendar = .current) -> DateInterval? {
        guard let first = days.first, let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last))
        else { return nil }
        return DateInterval(start: calendar.startOfDay(for: first), end: end)
    }

    /// Short weekday names, starting on the calendar's first weekday.
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.shortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    /// Dated tasks keyed by the start of their due day. An event is listed on every day it overlaps.
    /// A repeating event is listed once per occurrence that overlaps `range`, as a copy moved there;
    /// without a range only its first occurrence is. Each day has events first by start time,
    /// then tasks in display order.
    static func tasksByDay(_ tasks: [TaskItem], in range: DateInterval? = nil, calendar: Calendar = .current) -> [Date: [TaskItem]] {
        var result: [Date: [TaskItem]] = [:]
        for task in tasks {
            let occurrences = range.map { task.occurrences(in: $0, calendar: calendar) } ?? [task]
            for occurrence in occurrences {
                for day in days(of: occurrence, calendar: calendar)
                // Occurrences longer than the gap between them would list the item twice on a day.
                where !(result[day]?.contains { $0.id == occurrence.id } ?? false) {
                    result[day, default: []].append(occurrence)
                }
            }
        }
        return result.mapValues { dayTasks in
            dayTasks.sorted { a, b in
                if a.isEvent != b.isEvent { return a.isEvent }
                return a.isEvent ? TaskFilter.sameDayOrder(a, b) : TaskFilter.displayOrder(a, b)
            }
        }
    }

    /// The start of each day a task is on: its due day, or every day an event overlaps (up to a year).
    static func days(of task: TaskItem, calendar: Calendar = .current) -> [Date] {
        guard let start = task.start, let end = task.end else {
            return task.due.map { [calendar.startOfDay(for: $0)] } ?? []
        }
        var days: [Date] = []
        var day = calendar.startOfDay(for: start)
        repeat {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        } while day < end && days.count < 366
        return days
    }

    /// Moves by whole months or weeks.
    static func step(_ date: Date, mode: CalendarMode, by value: Int, calendar: Calendar = .current) -> Date {
        let component: Calendar.Component = mode == .month ? .month : .weekOfYear
        return calendar.date(byAdding: component, value: value, to: date) ?? date
    }

    static func startOfWeek(containing date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day) ?? day
    }

    private static func days(from start: Date, count: Int, calendar: Calendar) -> [Date] {
        (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
}

/// Where an event block sits in a day column of the week time grid.
struct EventPlacement: Equatable {
    let id: TaskItem.ID
    /// Minutes since midnight, clipped to the day.
    let startMinute: Int
    let endMinute: Int
    /// Overlapping events share the column width side by side.
    let column: Int
    let columnCount: Int
}

/// Lays out timed events in a day, kept free of SwiftUI so it can be tested.
enum EventLayout {
    static let minutesPerDay = 24 * 60
    /// Short events still get a block tall enough to click.
    static let minimumMinutes = 15
    static let snapMinutes = 15

    static func placements(for events: [TaskItem], on day: Date, calendar: Calendar = .current) -> [EventPlacement] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        // Wall-clock minutes, so blocks line up with the hour labels on daylight-saving days too.
        let spans: [(id: TaskItem.ID, start: Int, end: Int)] = events
            .compactMap { event in
                guard let start = event.start, let end = event.end, start < dayEnd, end > dayStart else { return nil }
                var from = start <= dayStart ? 0 : minuteOfDay(start, calendar: calendar)
                var to = end >= dayEnd ? minutesPerDay : minuteOfDay(end, calendar: calendar)
                to = min(max(to, from + minimumMinutes), minutesPerDay)
                from = min(from, to - minimumMinutes)
                return (event.id, from, to)
            }
            .sorted { ($0.start, -$0.end) < ($1.start, -$1.end) }

        var placements: [EventPlacement] = []
        var cluster: [(id: TaskItem.ID, start: Int, end: Int, column: Int)] = []
        var columnEnds: [Int] = []
        var clusterEnd = 0

        func closeCluster() {
            placements += cluster.map {
                EventPlacement(id: $0.id, startMinute: $0.start, endMinute: $0.end,
                               column: $0.column, columnCount: columnEnds.count)
            }
            cluster = []
            columnEnds = []
        }

        for span in spans {
            if span.start >= clusterEnd {
                closeCluster()
            }
            let column = columnEnds.firstIndex { $0 <= span.start } ?? columnEnds.count
            if column == columnEnds.count {
                columnEnds.append(span.end)
            } else {
                columnEnds[column] = span.end
            }
            cluster.append((span.id, span.start, span.end, column))
            clusterEnd = max(clusterEnd, span.end)
        }
        closeCluster()
        return placements
    }

    /// The minute of the day at a vertical offset in the grid, snapped down to 15 minutes.
    static func snappedMinute(atY y: Double, hourHeight: Double) -> Int {
        guard hourHeight > 0 else { return 0 }
        let minute = Int((y / hourHeight * 60).rounded(.down))
        let snapped = (minute / snapMinutes) * snapMinutes
        return min(max(snapped, 0), minutesPerDay - snapMinutes)
    }

    /// The minutes a drag across the grid covers, snapped outward to 15 minutes. Works in
    /// either direction and is always at least 15 minutes long.
    static func draggedRange(fromY: Double, toY: Double, hourHeight: Double) -> (start: Int, end: Int) {
        guard hourHeight > 0 else { return (0, snapMinutes) }
        let top = min(fromY, toY), bottom = max(fromY, toY)
        var start = snappedMinute(atY: top, hourHeight: hourHeight)
        let bottomMinute = (bottom / hourHeight * 60).rounded(.up)
        var end = Int((bottomMinute / Double(snapMinutes)).rounded(.up)) * snapMinutes
        end = min(max(end, start + snapMinutes), minutesPerDay)
        start = min(start, end - snapMinutes)
        return (start, end)
    }

    /// The time on `day` at a minute of the day.
    static func date(on day: Date, minute: Int, calendar: Calendar = .current) -> Date {
        let dayStart = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: dayStart) ?? dayStart
    }

    private static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let time = calendar.dateComponents([.hour, .minute], from: date)
        return (time.hour ?? 0) * 60 + (time.minute ?? 0)
    }
}
