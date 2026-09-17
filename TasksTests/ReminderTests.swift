import Foundation
import Testing
@testable import Tasks

private func at(_ day: String, hour: Int, minute: Int = 0) -> Date {
    let start = Calendar.current.startOfDay(for: TaskDates.parse(day)!)
    return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: start)!
}

private let now = at("2026-09-18", hour: 12)

private func timedTask(_ title: String = "a", hour: Int, alert: TaskAlert = .atTime, done: Bool = false) -> TaskItem {
    TaskItem(title: title, done: done, due: TaskDates.parse("2026-09-19"), dueTime: TimeOfDay(hour: hour), alert: alert)
}

struct ReminderTests {
    @Test func timedTaskFiresAtItsDueTime() {
        let reminders = Reminders.reminders(for: [timedTask(hour: 8)], now: now)
        #expect(reminders.map(\.fireDate) == [at("2026-09-19", hour: 8)])
        #expect(reminders.first?.body == "Due \(at("2026-09-19", hour: 8).formatted(.dateTime.hour().minute()))")
    }

    @Test(arguments: [(TaskAlert.minutesBefore(10), 7, 50), (.minutesBefore(60), 7, 0)])
    func alertMovesTheFireDateEarlier(alert: TaskAlert, hour: Int, minute: Int) {
        let reminders = Reminders.reminders(for: [timedTask(hour: 8, alert: alert)], now: now)
        #expect(reminders.map(\.fireDate) == [at("2026-09-19", hour: hour, minute: minute)])
    }

    @Test func eventFiresBeforeItsStart() {
        let event = TaskItem(title: "Lecture", start: at("2026-09-19", hour: 9), alert: .minutesBefore(15))
        let reminders = Reminders.reminders(for: [event], now: now)
        #expect(reminders.map(\.fireDate) == [at("2026-09-19", hour: 8, minute: 45)])
        #expect(reminders.first?.title == "Lecture")
    }

    @Test func skipsUntimedDoneAndSilencedItems() {
        let tasks = [
            TaskItem(title: "untimed", due: TaskDates.parse("2026-09-19")),
            TaskItem(title: "undated"),
            timedTask(hour: 8, done: true),
            timedTask(hour: 9, alert: .none),
            TaskItem(title: "silent event", start: at("2026-09-19", hour: 9), alert: .none),
        ]
        #expect(Reminders.reminders(for: tasks, now: now).isEmpty)
    }

    @Test func dropsPastAndFarFutureFireDates() {
        let tasks = [
            TaskItem(title: "past", start: at("2026-09-18", hour: 11)),
            TaskItem(title: "alert already passed", start: at("2026-09-18", hour: 12, minute: 30), alert: .minutesBefore(60)),
            TaskItem(title: "far", start: at("2026-10-30", hour: 9)),
        ]
        #expect(Reminders.reminders(for: tasks, now: now).isEmpty)
    }

    @Test func repeatingEventGivesOnePerOccurrenceInTheHorizon() {
        let event = TaskItem(title: "Standup", start: at("2026-09-01", hour: 9), recurrence: Recurrence(frequency: .daily))
        let reminders = Reminders.reminders(for: [event], now: now, horizon: 3 * 24 * 3600)
        #expect(reminders.map(\.fireDate) == [
            at("2026-09-19", hour: 9), at("2026-09-20", hour: 9), at("2026-09-21", hour: 9),
        ])
        #expect(Set(reminders.map(\.id)).count == 3)
    }

    @Test func sortedSoonestFirstAndCapped() {
        let tasks = [timedTask("late", hour: 20), timedTask("early", hour: 7), timedTask("mid", hour: 13)]
        let reminders = Reminders.reminders(for: tasks, now: now, limit: 2)
        #expect(reminders.map(\.title) == ["early", "mid"])
    }

    @Test func idsStayStableAcrossEditsThatKeepTheTime() {
        var task = timedTask(hour: 8)
        let before = Reminders.reminders(for: [task], now: now).map(\.id)
        task.title = "renamed"
        task.alert = .minutesBefore(5)
        #expect(Reminders.reminders(for: [task], now: now).map(\.id) == before)
    }
}
