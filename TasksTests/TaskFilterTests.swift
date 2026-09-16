import Foundation
import Testing
@testable import Tasks

private func day(_ string: String) -> Date {
    Calendar.current.startOfDay(for: TaskDates.parse(string)!)
}

private let now = day("2026-09-15").addingTimeInterval(10 * 3600)
private let overdue = TaskItem(title: "Overdue", due: day("2026-09-10"), createdAt: day("2026-09-01"))
private let dueToday = TaskItem(title: "Today", due: day("2026-09-15"), createdAt: day("2026-09-02"))
private let later = TaskItem(title: "Later", due: day("2026-09-20"), createdAt: day("2026-09-03"))
private let someday = TaskItem(title: "Someday", notes: "no due date", createdAt: day("2026-09-04"))
private let finished = TaskItem(title: "Finished", done: true, due: day("2026-09-01"), createdAt: day("2026-08-30"))
private let sample = [finished, someday, later, dueToday, overdue]

private func at(_ string: String, _ hour: Double) -> Date {
    day(string).addingTimeInterval(hour * 3600)
}

// `now` is 10:00 on Sep 15.
private let morningEvent = TaskItem(title: "Morning", start: at("2026-09-15", 8), end: at("2026-09-15", 9))
private let ongoingEvent = TaskItem(title: "Ongoing", start: at("2026-09-15", 9.5), end: at("2026-09-15", 11))
private let lunchEvent = TaskItem(title: "Lunch", start: at("2026-09-15", 12), end: at("2026-09-15", 13))
private let overnightEvent = TaskItem(title: "Overnight", start: at("2026-09-14", 22), end: at("2026-09-15", 11))
private let futureEvent = TaskItem(title: "Future", start: at("2026-09-20", 9), end: at("2026-09-20", 10))
private let events = [futureEvent, lunchEvent, morningEvent, overnightEvent, ongoingEvent]

struct TaskFilterTests {
    private func titles(_ filter: TaskFilter, search: String = "") -> [String] {
        filter.apply(to: sample, search: search, now: now).map(\.title)
    }

    @Test func allSortsOpenFirstThenByDueDate() {
        #expect(titles(.all) == ["Overdue", "Today", "Later", "Someday", "Finished"])
    }

    @Test func todayIncludesOverdue() {
        #expect(titles(.today) == ["Overdue", "Today"])
    }

    @Test func upcomingOnlyHasFutureOpenTasks() {
        #expect(titles(.upcoming) == ["Later"])
    }

    @Test func completedOnlyHasDoneTasks() {
        #expect(titles(.completed) == ["Finished"])
    }

    @Test func searchMatchesTitleAndNotesIgnoringCase() {
        #expect(titles(.all, search: "DUE") == ["Overdue", "Someday"])
    }

    @Test func homeListPicksMostSpecificFilter() {
        #expect(TaskFilter.home(for: overdue, now: now) == .today)
        #expect(TaskFilter.home(for: dueToday, now: now) == .today)
        #expect(TaskFilter.home(for: later, now: now) == .upcoming)
        #expect(TaskFilter.home(for: someday, now: now) == .all)
        #expect(TaskFilter.home(for: finished, now: now) == .completed)
    }

    @Test func overdueIgnoresDoneTasks() {
        #expect(overdue.isOverdue(now: now))
        #expect(!dueToday.isOverdue(now: now))
        #expect(!finished.isOverdue(now: now))
    }

    @Test func todayHasEventsThatHaveNotEnded() {
        let titles = TaskFilter.today.apply(to: events + [dueToday], now: now).map(\.title)
        #expect(titles == ["Overnight", "Ongoing", "Lunch", "Today"])
    }

    @Test func upcomingHasFutureEventsAndCompletedHasNone() {
        #expect(TaskFilter.upcoming.apply(to: events + [later], now: now).map(\.title) == ["Future", "Later"])
        #expect(TaskFilter.completed.apply(to: events + [finished], now: now).map(\.title) == ["Finished"])
    }

    @Test func eventsBeforeTasksOnADayAndEndedEventsLast() {
        let titles = TaskFilter.all.apply(to: [morningEvent, dueToday, lunchEvent, finished], now: now).map(\.title)
        #expect(titles == ["Lunch", "Today", "Finished", "Morning"])
    }

    @Test func homeListForEvents() {
        #expect(TaskFilter.home(for: ongoingEvent, now: now) == .today)
        #expect(TaskFilter.home(for: overnightEvent, now: now) == .today)
        #expect(TaskFilter.home(for: futureEvent, now: now) == .upcoming)
        #expect(TaskFilter.home(for: morningEvent, now: now) == .all)
        #expect(!morningEvent.isOverdue(now: now))
    }
}
