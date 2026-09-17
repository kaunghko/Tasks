import CoreGraphics
import Foundation
import Testing
@testable import Tasks

private func day(_ string: String) -> Date {
    Calendar.current.startOfDay(for: TaskDates.parse(string)!)
}

struct CalendarDropTests {
    // A week layout: two all-day cells above two hour-grid columns scrolled up by 400pt,
    // so the grid's frame runs on under the all-day row.
    private let zones: [CalendarDropZone: CGRect] = [
        .allDay(day("2026-09-15")): CGRect(x: 0, y: 0, width: 100, height: 40),
        .allDay(day("2026-09-16")): CGRect(x: 100, y: 0, width: 100, height: 40),
        .timeline(day("2026-09-15")): CGRect(x: 0, y: -360, width: 100, height: 1152),
        .timeline(day("2026-09-16")): CGRect(x: 100, y: -360, width: 100, height: 1152),
        .undated: CGRect(x: 200, y: 0, width: 80, height: 600),
    ]

    private func target(_ x: CGFloat, _ y: CGFloat, isEvent: Bool = true, grab: CGFloat = 0) -> CalendarDropTarget? {
        CalendarDrop.target(at: CGPoint(x: x, y: y), zones: zones, isEvent: isEvent, grabOffsetY: grab, hourHeight: 48)
    }

    @Test func allDayRowWinsOverTheGridBeneathIt() {
        #expect(target(150, 20) == .day(day("2026-09-16")))
        #expect(target(150, 20, isEvent: false) == .allDay(day("2026-09-16")))
    }

    @Test func monthCellsKeepTheTime() {
        let zones: [CalendarDropZone: CGRect] = [.day(day("2026-09-15")): CGRect(x: 0, y: 0, width: 100, height: 100)]
        let target = CalendarDrop.target(at: CGPoint(x: 50, y: 50), zones: zones, isEvent: false, grabOffsetY: 0, hourHeight: 48)
        #expect(target == .day(day("2026-09-15")))
    }

    @Test func eventsLandAtTheSnappedTimeOfTheirTopEdge() {
        // y 240 is 600pt below midnight = 12:30; grabbed 30pt below the top puts the top at 11:52 → 12:00.
        #expect(target(50, 240) == .time(day: day("2026-09-15"), minute: 750))
        #expect(target(150, 240, grab: 30) == .time(day: day("2026-09-16"), minute: 720))
    }

    @Test func tasksOverTheGridLandAtThatTime() {
        #expect(target(150, 240, isEvent: false, grab: 30) == .time(day: day("2026-09-16"), minute: 720))
    }

    @Test func onlyTasksCanLoseTheirDate() {
        #expect(target(240, 100, isEvent: false) == .undated)
        #expect(target(240, 100) == nil)
        #expect(target(500, 100) == nil)
    }

    @Test(arguments: [(-50.0, 0), (5.0, 0), (6.0, 15), (17.0, 15), (18.0, 30), (5000.0, 1425)])
    func startMinuteRoundsToNearestQuarterHour(topY: Double, minute: Int) {
        #expect(CalendarDrop.startMinute(topY: topY, hourHeight: 48) == minute)
    }
}
