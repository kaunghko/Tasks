import Foundation

/// A notification to schedule for a timed task or an event occurrence.
struct Reminder: Hashable {
    /// Stable across reschedules: the item's id and the time it's for.
    var id: String
    var fireDate: Date
    var title: String
    var body: String
}

enum Reminders {
    static let horizon: TimeInterval = 14 * 24 * 3600
    /// macOS keeps about 64 pending notifications per app; stay below that.
    static let limit = 60

    /// The upcoming notifications for `tasks`, soonest first. Done tasks, tasks without a due time
    /// and items with no alert are skipped. A repeating event gives one per occurrence within the horizon.
    static func reminders(
        for tasks: [TaskItem],
        now: Date = .now,
        horizon: TimeInterval = horizon,
        limit: Int = limit,
        calendar: Calendar = .current
    ) -> [Reminder] {
        let window = DateInterval(start: now, duration: horizon)
        var result: [Reminder] = []
        for task in tasks {
            guard let offset = task.alert.offset else { continue }
            if task.isEvent {
                // Stretch the range back so occurrences whose alert is before their start still count.
                let range = DateInterval(start: now, duration: horizon + offset)
                for occurrence in task.occurrences(in: range, calendar: calendar) {
                    guard let start = occurrence.start else { continue }
                    result.append(reminder(for: occurrence, at: start, offset: offset))
                }
            } else if !task.done, let due = task.due, let time = task.dueTime?.on(due, calendar: calendar) {
                result.append(reminder(for: task, at: time, offset: offset))
            }
        }
        return result
            .filter { $0.fireDate > now && $0.fireDate <= window.end }
            .sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
            .prefix(limit)
            .map { $0 }
    }

    private static func reminder(for item: TaskItem, at time: Date, offset: TimeInterval) -> Reminder {
        var body = item.timeRangeLabel ?? item.dueTimeLabel.map { "Due \($0)" } ?? ""
        // An alert a day or more ahead also names the day, such as "Sep 22 · 09:00–10:00".
        if offset >= 24 * 3600 {
            body = "\(time.formatted(.dateTime.month(.abbreviated).day())) · \(body)"
        }
        return Reminder(
            id: "\(item.id.uuidString)|\(TaskDates.timestampString(time))",
            fireDate: time.addingTimeInterval(-offset),
            title: item.title.isEmpty ? (item.isEvent ? "Event" : "Task") : item.title,
            body: body
        )
    }
}
