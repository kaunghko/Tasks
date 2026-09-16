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

    @Test func multiDayEventIsOnEveryDayItOverlaps() {
        let trip = TaskItem(
            title: "Trip",
            start: day("2026-09-15").addingTimeInterval(20 * 3600),
            end: day("2026-09-18") // Midnight: not on the 18th.
        )
        let task = TaskItem(title: "Pack", due: day("2026-09-16"))

        let grouped = CalendarGrid.tasksByDay([task, trip])
        #expect(grouped.keys.sorted() == [day("2026-09-15"), day("2026-09-16"), day("2026-09-17")])
        #expect(grouped[day("2026-09-16")]?.map(\.title) == ["Trip", "Pack"])
    }

    private func event(_ title: String, _ from: Double, _ to: Double, on date: String = "2026-09-15") -> TaskItem {
        TaskItem(
            title: title,
            start: day(date).addingTimeInterval(from * 3600),
            end: day(date).addingTimeInterval(to * 3600)
        )
    }

    @Test func overlappingEventsSitSideBySide() {
        let a = event("A", 9, 11)
        let b = event("B", 10, 12)
        let c = event("C", 11, 12)
        let d = event("D", 13, 14)

        let placements = EventLayout.placements(for: [d, c, b, a], on: day("2026-09-15"))
        let byID = Dictionary(uniqueKeysWithValues: placements.map { ($0.id, $0) })

        #expect(byID[a.id] == EventPlacement(id: a.id, startMinute: 540, endMinute: 660, column: 0, columnCount: 2))
        #expect(byID[b.id] == EventPlacement(id: b.id, startMinute: 600, endMinute: 720, column: 1, columnCount: 2))
        // Starts when A ends, so it reuses A's column.
        #expect(byID[c.id] == EventPlacement(id: c.id, startMinute: 660, endMinute: 720, column: 0, columnCount: 2))
        #expect(byID[d.id] == EventPlacement(id: d.id, startMinute: 780, endMinute: 840, column: 0, columnCount: 1))
    }

    @Test func placementsClipToTheDayAndKeepAMinimumHeight() {
        let overnight = event("Overnight", 22, 26)
        let blip = TaskItem(title: "Blip", start: day("2026-09-16").addingTimeInterval(23.95 * 3600),
                            end: day("2026-09-16").addingTimeInterval(23.97 * 3600))

        let first = EventLayout.placements(for: [overnight], on: day("2026-09-15"))
        let second = EventLayout.placements(for: [overnight, blip], on: day("2026-09-16"))
        let other = EventLayout.placements(for: [overnight], on: day("2026-09-17"))

        #expect(first.map(\.startMinute) == [1320])
        #expect(first.map(\.endMinute) == [1440])
        #expect(second.first { $0.id == overnight.id }?.startMinute == 0)
        #expect(second.first { $0.id == overnight.id }?.endMinute == 120)
        #expect(second.first { $0.id == blip.id }.map { $0.endMinute - $0.startMinute } == 15)
        #expect(second.first { $0.id == blip.id }?.endMinute == 1440)
        #expect(other.isEmpty)
    }

    @Test(arguments: [(0.0, 0), (47.0, 45), (48.0, 60), (60.0, 75), (-5.0, 0), (5000.0, 1425)])
    func snappedMinuteRoundsDownToQuarterHours(y: Double, minute: Int) {
        #expect(EventLayout.snappedMinute(atY: y, hourHeight: 48) == minute)
    }

    // 48pt per hour, so 12pt is 15 minutes.
    @Test(arguments: [
        (100.0, 200.0, 120, 255),  // Down: 02:05 to 04:10 widens to 02:00–04:15.
        (200.0, 100.0, 120, 255),  // Up gives the same range.
        (100.0, 102.0, 120, 135),  // A tiny drag is still 15 minutes.
        (1140.0, 5000.0, 1425, 1440), // Past the bottom stops at midnight.
        (1151.0, 1152.0, 1425, 1440),
        (-20.0, 24.0, 0, 30),
    ])
    func draggedRangeSnapsOutward(fromY: Double, toY: Double, start: Int, end: Int) {
        let range = EventLayout.draggedRange(fromY: fromY, toY: toY, hourHeight: 48)
        #expect(range.start == start)
        #expect(range.end == end)
    }
}

