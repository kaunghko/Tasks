import Foundation
import Testing
@testable import Tasks

private func day(_ string: String) -> Date {
    Calendar.current.startOfDay(for: TaskDates.parse(string)!)
}

private func at(_ string: String, hour: Int, minute: Int = 0) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day(string))!
}

private func occurrences(_ rule: Recurrence, from anchor: String, count: Int) -> [Date] {
    var result: [Date] = []
    rule.forEachOccurrence(from: day(anchor)) { date in
        result.append(date)
        return result.count < count
    }
    return result
}

struct RecurrenceTests {
    @Test(arguments: [
        // 2026-09-15 is a Tuesday.
        (Recurrence(frequency: .daily), ["2026-09-15", "2026-09-16", "2026-09-17"]),
        (Recurrence(frequency: .daily, interval: 3), ["2026-09-15", "2026-09-18", "2026-09-21"]),
        (Recurrence(frequency: .weekly, interval: 2), ["2026-09-15", "2026-09-29", "2026-10-13"]),
        (Recurrence(frequency: .weekly, weekdays: [.mon, .wed]), ["2026-09-15", "2026-09-16", "2026-09-21", "2026-09-23"]),
        (Recurrence(frequency: .yearly), ["2026-09-15", "2027-09-15"]),
    ])
    func occurrencesFollowTheRule(rule: Recurrence, expected: [String]) {
        #expect(occurrences(rule, from: "2026-09-15", count: expected.count) == expected.map(day))
    }

    @Test func untilIsTheLastDayIncluded() {
        let rule = Recurrence(frequency: .daily, until: day("2026-09-16"))
        #expect(occurrences(rule, from: "2026-09-15", count: 5) == ["2026-09-15", "2026-09-16"].map(day))
        #expect(rule.next(after: day("2026-09-16"), anchor: day("2026-09-15")) == nil)
    }

    @Test func everyOtherWeekOnWeekdaysSkipsAWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let rule = Recurrence(frequency: .weekly, interval: 2, weekdays: [.mon, .fri])
        var result: [Date] = []
        rule.forEachOccurrence(from: day("2026-09-14"), calendar: calendar) { date in
            result.append(date)
            return result.count < 4
        }
        #expect(result == ["2026-09-14", "2026-09-18", "2026-09-28", "2026-10-02"].map(day))
    }

    @Test func monthlyOnThe31stComesBackAfterShortMonths() {
        let dates = occurrences(Recurrence(frequency: .monthly), from: "2027-01-31", count: 3)
        #expect(dates == ["2027-01-31", "2027-02-28", "2027-03-31"].map(day))
    }

    @Test func occurrencesKeepWallClockTimeAcrossDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        // Clocks go back on Nov 1, 2026 in New York.
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 9)))
        var dates: [Date] = []
        Recurrence(frequency: .daily).forEachOccurrence(from: start, calendar: calendar) { date in
            dates.append(date)
            return dates.count < 4
        }
        #expect(dates.map { calendar.component(.hour, from: $0) } == [9, 9, 9, 9])
    }

    @Test func summaryDescribesTheRule() {
        #expect(Recurrence(frequency: .daily).summary == "Daily")
        #expect(Recurrence(frequency: .monthly, interval: 3).summary == "Every 3 months")
    }

    @Test func weekdaysShiftAndWrap() {
        let rule = Recurrence(frequency: .weekly, weekdays: [.fri, .sat]).shifted(byDays: 2)
        #expect(rule.weekdays == [.sun, .mon])
    }

    // MARK: Tasks roll forward

    // `init` sets `done` without rolling, so `rollForward(now:)` can run at a fixed time.
    @Test func checkingOffMovesToTheNextDayAndResetsSubtasks() {
        var task = TaskItem(
            title: "Stretch", subtasks: [Subtask(title: "Legs", done: true)], done: true,
            due: day("2026-09-15"), recurrence: Recurrence(frequency: .daily)
        )
        task.rollForward(now: at("2026-09-15", hour: 10))

        #expect(!task.done)
        #expect(task.due == day("2026-09-16"))
        #expect(task.subtasks.allSatisfy { !$0.done })
    }

    @Test func overdueTaskLandsOnTodayNotInThePast() {
        var task = TaskItem(title: "Stretch", done: true, due: day("2026-09-10"), recurrence: Recurrence(frequency: .daily))
        task.rollForward(now: at("2026-09-15", hour: 10))

        #expect(!task.done)
        #expect(task.due == day("2026-09-15"))
    }

    @Test func nonRepeatingTaskStaysDone() {
        var task = TaskItem(title: "Once", due: day("2099-01-05"))
        task.done = true
        #expect(task.done)
        #expect(task.due == day("2099-01-05"))
    }

    @Test func futureTaskMovesOneStep() {
        var task = TaskItem(title: "Report", due: day("2099-01-05"), recurrence: Recurrence(frequency: .weekly))
        task.done = true

        #expect(!task.done)
        #expect(task.due == day("2099-01-12"))
    }

    @Test func taskStaysDoneOnceTheRuleEnds() {
        var task = TaskItem(
            title: "Report", due: day("2099-01-05"),
            recurrence: Recurrence(frequency: .weekly, until: day("2099-01-10"))
        )
        task.done = true

        #expect(task.done)
        #expect(task.due == day("2099-01-05"))
    }

    @Test func decodingDoneDoesNotRoll() throws {
        let json = #"{"tasks":[{"title":"A","done":true,"due":"2026-09-15","repeat":{"frequency":"daily"}}]}"#
        let task = try #require(try TaskFile.decode(Data(json.utf8)).tasks.first)
        #expect(task.done)
        #expect(task.due == day("2026-09-15"))
    }

    // MARK: Events repeat as occurrences

    private let lecture = TaskItem(
        title: "Lecture",
        start: at("2026-09-14", hour: 9),
        end: at("2026-09-14", hour: 10, minute: 15),
        recurrence: Recurrence(frequency: .weekly, weekdays: [.mon, .wed])
    )

    @Test func occurrencesInARange() throws {
        let range = DateInterval(start: day("2026-09-16"), end: day("2026-09-22"))
        let found = lecture.occurrences(in: range)

        #expect(found.map(\.start) == [at("2026-09-16", hour: 9), at("2026-09-21", hour: 9)])
        #expect(found.map(\.end) == [at("2026-09-16", hour: 10, minute: 15), at("2026-09-21", hour: 10, minute: 15)])
        #expect(found.allSatisfy { $0.id == lecture.id })
    }

    @Test func currentOccurrenceIsTheFirstThatHasNotEnded() {
        #expect(lecture.currentOccurrence(now: at("2026-09-16", hour: 10)).start == at("2026-09-16", hour: 9))
        #expect(lecture.currentOccurrence(now: at("2026-09-16", hour: 11)).start == at("2026-09-21", hour: 9))
        #expect(lecture.currentOccurrence(now: at("2026-09-13", hour: 11)) == lecture)
    }

    @Test func currentOccurrenceIsTheLastOnceTheRuleEnds() {
        var event = lecture
        event.recurrence?.until = day("2026-09-16")
        #expect(event.currentOccurrence(now: at("2026-10-01", hour: 9)).start == at("2026-09-16", hour: 9))
    }

    @Test func movingASeriesShiftsItsWeekdays() {
        var event = lecture
        event.moveSeries(byDays: 1)

        #expect(event.start == at("2026-09-15", hour: 9))
        #expect(event.end == at("2026-09-15", hour: 10, minute: 15))
        #expect(event.recurrence?.weekdays == [.tue, .thu])
    }

    @Test func movingASeriesToAStartKeepsItsLength() {
        var event = lecture
        event.moveSeries(toStart: at("2026-09-16", hour: 14))

        #expect(event.start == at("2026-09-16", hour: 14))
        #expect(event.end == at("2026-09-16", hour: 15, minute: 15))
        #expect(event.recurrence?.weekdays == [.wed, .fri])
    }

    @Test func pickingWeekdaysWithoutTheCurrentDayMovesToTheNextPickedDay() {
        var event = lecture
        event.repeatWeekdays = [.thu, .fri]

        #expect(event.start == at("2026-09-17", hour: 9))
        #expect(event.recurrence?.weekdays == [.thu, .fri])
    }

    @Test func choosingARuleForAnUndatedTaskMakesItDueToday() {
        var task = TaskItem(title: "Water plants")
        task.repeatFrequency = .weekly
        #expect(task.due == Calendar.current.startOfDay(for: .now))

        task.hasDueDate = false
        #expect(task.recurrence == nil)
    }
}
