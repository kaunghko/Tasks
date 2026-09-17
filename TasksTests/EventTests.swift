import Foundation
import Testing
@testable import Tasks

private func day(_ string: String) -> Date {
    Calendar.current.startOfDay(for: TaskDates.parse(string)!)
}

private func at(_ string: String, hour: Int, minute: Int = 0) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day(string))!
}

struct EventTests {
    private let lecture = TaskItem(
        title: "Lecture",
        start: at("2026-09-15", hour: 9),
        end: at("2026-09-15", hour: 10, minute: 15)
    )

    @Test func moveToDayKeepsTimeAndLength() {
        var event = lecture
        event.move(toDay: day("2026-09-18"))

        #expect(event.start == at("2026-09-18", hour: 9))
        #expect(event.end == at("2026-09-18", hour: 10, minute: 15))
        #expect(event.due == day("2026-09-18"))
    }

    @Test func moveToDayKeepsWallClockTimeAcrossDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        // Clocks go back on Nov 1, 2026 in New York.
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 9)))
        var event = TaskItem(title: "Standup", start: start, end: start.addingTimeInterval(1800))

        event.move(toDay: start.addingTimeInterval(4 * 86400), calendar: calendar)

        let moved = try #require(event.start)
        #expect(calendar.component(.hour, from: moved) == 9)
        #expect(calendar.component(.day, from: moved) == 3)
        #expect(event.end == moved.addingTimeInterval(1800))
    }

    @Test func movingTheStartKeepsTheLength() {
        var event = lecture
        event.eventStart = at("2026-09-16", hour: 14)

        #expect(event.end == at("2026-09-16", hour: 15, minute: 15))
        #expect(event.due == day("2026-09-16"))
    }

    @Test func endBeforeStartBecomesAQuarterHour() {
        var event = lecture
        event.eventEnd = at("2026-09-15", hour: 8)

        #expect(event.end == at("2026-09-15", hour: 9, minute: 15))
    }

    @Test func switchingKinds() {
        var item = TaskItem(title: "Review", done: true, due: day("2026-09-20"))

        item.isEventKind = true
        #expect(item.isEvent)
        #expect(!item.done)
        #expect(item.due == day("2026-09-20"))
        #expect(item.end.map { $0.timeIntervalSince(item.start!) } == TaskItem.defaultEventDuration)

        item.isEventKind = false
        #expect(!item.isEvent)
        #expect(item.end == nil)
        #expect(item.due == day("2026-09-20"))
    }

    @Test(arguments: [(10, 11), (23, 23)])
    func defaultStartIsTheNextWholeHour(nowHour: Int, startHour: Int) {
        let now = at("2026-09-15", hour: nowHour, minute: 30)
        let start = TaskItem.defaultEventStart(on: day("2026-09-20"), now: now)

        #expect(start == at("2026-09-20", hour: startHour))
    }

    @Test func tasksMoveToDayAndIgnoreTimeMoves() {
        var task = TaskItem(title: "Essay", due: day("2026-09-15"))
        task.move(toDay: at("2026-09-17", hour: 15))
        task.move(toStart: at("2026-09-19", hour: 9))

        #expect(task.due == day("2026-09-17"))
        #expect(!task.isEvent)
    }

    @Test func moveToTimeSetsATasksDueDayAndTime() {
        var task = TaskItem(title: "Essay", due: day("2026-09-15"))
        task.move(toTime: at("2026-09-17", hour: 15, minute: 30))

        #expect(task.due == day("2026-09-17"))
        #expect(task.dueTime == TimeOfDay(hour: 15, minute: 30))
        #expect(!task.isEvent)
    }

    @Test func moveToTimeKeepsAnEventsLength() {
        var event = lecture
        event.move(toTime: at("2026-09-16", hour: 14))

        #expect(event.start == at("2026-09-16", hour: 14))
        #expect(event.end == at("2026-09-16", hour: 15, minute: 15))
        #expect(event.dueTime == nil)
    }

    @Test func makeEventRestoresPreviousTimesOnTheCurrentDueDay() {
        var item = lecture
        let previous = (start: item.start!, end: item.end!)
        item.makeTask()
        item.dueDay = day("2026-09-18")

        item.makeEvent(previous: previous)

        #expect(item.start == at("2026-09-18", hour: 9))
        #expect(item.end == at("2026-09-18", hour: 10, minute: 15))
    }

    @Test func makeTaskRestoresDoneAndKeepsTheDay() {
        var item = lecture
        item.makeTask(done: true)

        #expect(!item.isEvent)
        #expect(item.done)
        #expect(item.due == day("2026-09-15"))
    }

    @Test func eventStartIsStableForTasks() {
        let task = TaskItem(title: "Essay", due: day("2026-09-15"))
        #expect(task.eventStart == day("2026-09-15"))
        #expect(task.eventStart == task.eventStart)
    }
}

