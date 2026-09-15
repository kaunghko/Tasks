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
}
