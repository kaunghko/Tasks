import Foundation
import Testing
@testable import Tasks

private func day(_ string: String) -> Date {
    Calendar.current.startOfDay(for: TaskDates.parse(string)!)
}

private func makeCalendar(firstWeekday: Int) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US")
    calendar.firstWeekday = firstWeekday
    return calendar
}

struct CalendarGridTests {
    // September 2026 starts on a Tuesday.
    @Test(arguments: [(1, "2026-08-30"), (2, "2026-08-31")])
    func monthGridIsSixContiguousWeeks(firstWeekday: Int, start: String) {
        let calendar = makeCalendar(firstWeekday: firstWeekday)
        let days = CalendarGrid.monthDays(containing: day("2026-09-15"), calendar: calendar)
        #expect(days.count == 42)
        #expect(days.first == day(start))
        #expect(calendar.component(.weekday, from: days[0]) == firstWeekday)
        #expect(days.contains(day("2026-09-01")))
        #expect(days.contains(day("2026-09-30")))
        for (a, b) in zip(days, days.dropFirst()) {
            #expect(calendar.dateComponents([.day], from: a, to: b).day == 1)
        }
    }

    @Test(arguments: [
        (1, "2026-09-15", "2026-09-13"),
        (2, "2026-09-15", "2026-09-14"),
        (2, "2026-09-13", "2026-09-07"),
    ])
    func weekStartsOnFirstWeekday(firstWeekday: Int, date: String, start: String) {
        let days = CalendarGrid.weekDays(containing: day(date), calendar: makeCalendar(firstWeekday: firstWeekday))
        #expect(days.count == 7)
        #expect(days.first == day(start))
        #expect(days.contains(day(date)))
    }

    @Test func weekdaySymbolsFollowFirstWeekday() {
        let symbols = CalendarGrid.weekdaySymbols(calendar: makeCalendar(firstWeekday: 2))
        #expect(symbols.count == 7)
        #expect(symbols.first == "Mon")
        #expect(symbols.last == "Sun")
    }

    @Test func tasksByDaySkipsUndatedAndSortsOpenFirst() {
        let done = TaskItem(title: "Done", done: true, due: day("2026-09-15"), createdAt: day("2026-09-01"))
        let open = TaskItem(title: "Open", due: day("2026-09-15"), createdAt: day("2026-09-02"))
        let later = TaskItem(title: "Later", due: day("2026-09-20"), createdAt: day("2026-09-03"))
        let undated = TaskItem(title: "Undated", createdAt: day("2026-09-04"))

        let grouped = CalendarGrid.tasksByDay([done, undated, later, open])
        #expect(grouped.count == 2)
        #expect(grouped[day("2026-09-15")]?.map(\.title) == ["Open", "Done"])
        #expect(grouped[day("2026-09-20")]?.map(\.title) == ["Later"])
    }

    @Test func stepCrossesMonthAndYearBoundaries() {
        #expect(CalendarGrid.step(day("2026-12-15"), mode: .month, by: 1) == day("2027-01-15"))
        #expect(CalendarGrid.step(day("2027-01-31"), mode: .month, by: 1) == day("2027-02-28"))
        #expect(CalendarGrid.step(day("2026-12-28"), mode: .week, by: 1) == day("2027-01-04"))
        #expect(CalendarGrid.step(day("2027-01-04"), mode: .week, by: -1) == day("2026-12-28"))
    }
}
