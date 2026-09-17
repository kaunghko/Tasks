import Foundation
import Testing
@testable import Tasks

private func day(_ string: String) -> Date {
    Calendar.current.startOfDay(for: TaskDates.parse(string)!)
}

private func at(_ string: String, hour: Int, minute: Int = 0) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day(string))!
}

/// Thursday, Sep 17, 2026, 10:00. Weeks start on Sunday and numeric dates read month first.
private let now = at("2026-09-17", hour: 10)

private let calendar: Calendar = {
    var calendar = Calendar.current
    calendar.firstWeekday = 1
    calendar.locale = Locale(identifier: "en_US")
    return calendar
}()

private func parse(_ text: String) -> DetectedSchedule? {
    ScheduleParser.parse(text, now: now, calendar: calendar)
}

struct ScheduleParserTests {
    @Test(arguments: [
        ("Report today", "Report", "2026-09-17"),
        ("Call mom, tomorrow", "Call mom", "2026-09-18"),
        ("Pay day after tomorrow", "Pay", "2026-09-19"),
        ("Lunch friday", "Lunch", "2026-09-18"),
        ("Review thursday", "Review", "2026-09-24"),
        ("Review this thursday", "Review", "2026-09-17"),
        ("Review next fri", "Review", "2026-09-25"),
        ("Essay due by fri", "Essay", "2026-09-18"),
        ("Plan next week", "Plan", "2026-09-20"),
        ("Budget next month", "Budget", "2026-10-01"),
        ("Renew in 3 days", "Renew", "2026-09-20"),
        ("Renew in 2 weeks", "Renew", "2026-10-01"),
        ("Submit sep 22", "Submit", "2026-09-22"),
        ("Submit 22nd of September", "Submit", "2026-09-22"),
        ("Submit September 22nd, 2027", "Submit", "2027-09-22"),
        ("Taxes sep 1", "Taxes", "2027-09-01"),
        ("Trip 2026-10-05", "Trip", "2026-10-05"),
        ("Trip 10/5", "Trip", "2026-10-05"),
    ])
    func findsDays(text: String, title: String, expected: String) throws {
        let detected = try #require(parse(text))
        #expect(detected.title == title)
        #expect(detected.day == day(expected))
        #expect(detected.start == nil)
        #expect(detected.recurrence == nil)
    }

    @Test(arguments: [
        ("Call at 3", "Call", TimeOfDay(hour: 15), TimeOfDay?.none),
        ("Standup 9:30am", "Standup", TimeOfDay(hour: 9, minute: 30), nil),
        ("Gym 07:00", "Gym", TimeOfDay(hour: 7), nil),
        ("Lunch noon", "Lunch", TimeOfDay(hour: 12), nil),
        ("Sleep midnight", "Sleep", TimeOfDay(hour: 0), nil),
        ("Dentist 3-4pm", "Dentist", TimeOfDay(hour: 15), TimeOfDay(hour: 16)),
        ("Sync from 11 to 1pm", "Sync", TimeOfDay(hour: 11), TimeOfDay(hour: 13)),
        ("Lecture 9:00–10:15", "Lecture", TimeOfDay(hour: 9), TimeOfDay(hour: 10, minute: 15)),
        ("Talk 10pm-1am", "Talk", TimeOfDay(hour: 22), TimeOfDay(hour: 1)),
    ])
    func findsTimes(text: String, title: String, start: TimeOfDay, end: TimeOfDay?) throws {
        let detected = try #require(parse(text))
        #expect(detected.title == title)
        #expect(detected.start == start)
        #expect(detected.end == end)
        #expect(detected.day == nil)
    }

    @Test func findsDayTimeAndLengthTogether() throws {
        let detected = try #require(parse("Dentist tomorrow at 3pm for 1h30m"))
        #expect(detected.title == "Dentist")
        #expect(detected.phrase == "tomorrow at 3pm for 1h30m")
        #expect(detected.day == day("2026-09-18"))
        #expect(detected.start == TimeOfDay(hour: 15))
        #expect(detected.duration == 5400)
    }

    @Test func tonightMeansEightUnlessTimed() throws {
        #expect(try #require(parse("Party tonight")).start == TimeOfDay(hour: 20))
        #expect(try #require(parse("Party tonight at 9")).start == TimeOfDay(hour: 21))
    }

    @Test(arguments: [
        ("Stretch daily", "Stretch", Recurrence(frequency: .daily)),
        ("Stretch every day", "Stretch", Recurrence(frequency: .daily)),
        ("Water every other day", "Water", Recurrence(frequency: .daily, interval: 2)),
        ("Standup every weekday", "Standup", Recurrence(frequency: .weekly, weekdays: [.mon, .tue, .wed, .thu, .fri])),
        ("Hike every weekend", "Hike", Recurrence(frequency: .weekly, weekdays: [.sat, .sun])),
        ("Review every 2 weeks", "Review", Recurrence(frequency: .weekly, interval: 2)),
        ("Class every mon, wed and fri", "Class", Recurrence(frequency: .weekly, weekdays: [.mon, .wed, .fri])),
        ("Laundry on sundays", "Laundry", Recurrence(frequency: .weekly, weekdays: [.sun])),
        ("Sync weekly on tue", "Sync", Recurrence(frequency: .weekly, weekdays: [.tue])),
        ("Rent monthly", "Rent", Recurrence(frequency: .monthly)),
        ("Checkup every 6 months", "Checkup", Recurrence(frequency: .monthly, interval: 6)),
        ("Renew yearly", "Renew", Recurrence(frequency: .yearly)),
        ("Lecture every tue thu until dec 17", "Lecture",
         Recurrence(frequency: .weekly, weekdays: [.tue, .thu], until: day("2026-12-17"))),
    ])
    func findsRepeatRules(text: String, title: String, rule: Recurrence) throws {
        let detected = try #require(parse(text))
        #expect(detected.title == title)
        #expect(detected.recurrence == rule)
    }

    @Test(arguments: [
        ("Pay rent every month on the 1st", "Pay rent", Recurrence.Frequency.monthly, "2026-10-01"),
        ("Backup every 15th", "Backup", .monthly, "2026-10-15"),
        ("Pay bills every 17th", "Pay bills", .monthly, "2026-09-17"),
        ("Birthday every sep 22", "Birthday", .yearly, "2026-09-22"),
    ])
    func repeatRulesOnADaySetTheFirstDay(text: String, title: String, frequency: Recurrence.Frequency, first: String) throws {
        let detected = try #require(parse(text))
        #expect(detected.title == title)
        #expect(detected.recurrence == Recurrence(frequency: frequency))
        #expect(detected.day == day(first))
    }

    @Test func weekdayRuleWithTime() throws {
        let detected = try #require(parse("Gym every mon wed 7am"))
        #expect(detected.title == "Gym")
        #expect(detected.phrase == "every mon wed 7am")
        #expect(detected.recurrence == Recurrence(frequency: .weekly, weekdays: [.mon, .wed]))
        #expect(detected.start == TimeOfDay(hour: 7))
    }

    @Test(arguments: [
        "Read 1984",
        "sat exam prep",
        "March madness",
        "Buy sunscreen",
        "Buy 3 eggs",
        "Q3: 10 items",
        "Chapter 3-4",
        "Stretch for 20 minutes",
        "Send PM notes",
        "until dec 17",
        "tomorrow",  // nothing would be left for a title
    ])
    func ignoresTextWithoutASchedule(text: String) {
        #expect(parse(text) == nil)
    }

    @Test func weekdayAbbreviationsNeedAPrefix() {
        #expect(parse("Meet on mon")?.day == day("2026-09-21"))
        #expect(parse("Meet mon") == nil)
    }

    // MARK: - Tasks

    @Test(arguments: [
        ("a new task tomorrow 8 am", "a new task", "2026-09-18", TimeOfDay(hour: 8)),
        ("Finish essay tonight", "Finish essay", "2026-09-17", TimeOfDay(hour: 20)),
        ("Call mom at 5", "Call mom", "2026-09-17", TimeOfDay(hour: 17)),
        ("Submit HW friday by 11:59pm", "Submit HW", "2026-09-18", TimeOfDay(hour: 23, minute: 59)),
    ])
    func timeBecomesATasksDueTime(text: String, title: String, expected: String, time: TimeOfDay) throws {
        var task = TaskItem(title: text)
        task.apply(try #require(parse(text)), now: now, calendar: calendar)

        #expect(!task.isEvent)
        #expect(task.title == title)
        #expect(task.due == day(expected))
        #expect(task.dueTime == time)
    }

    @Test func dayAloneKeepsATasksDueTime() throws {
        var task = TaskItem(title: "Standup friday", due: day("2026-09-17"), dueTime: TimeOfDay(hour: 9))
        task.apply(try #require(parse(task.title)), now: now, calendar: calendar)

        #expect(task.due == day("2026-09-18"))
        #expect(task.dueTime == TimeOfDay(hour: 9))
    }

    @Test func byBeforeATimeLeavesTheTitle() throws {
        #expect(try #require(parse("Submit HW by 5pm")).title == "Submit HW")
    }

    // MARK: - Applying

    private func lecture(_ title: String) -> TaskItem {
        TaskItem(title: title, start: at("2026-09-15", hour: 9), end: at("2026-09-15", hour: 10, minute: 15))
    }

    @Test(arguments: ["Dentist tomorrow 3-4pm", "Finish essay tonight", "Call mom at 5", "Gym every mon wed 7am"])
    func applyingNeverTurnsATaskIntoAnEvent(text: String) throws {
        // Even a result with times, as an event's title would give.
        var task = TaskItem(title: text)
        task.apply(try #require(parse(text)), now: now, calendar: calendar)
        #expect(!task.isEvent)
        #expect(task.start == nil)
        #expect(task.end == nil)
    }

    @Test func applyingKeepsAnEventAnEvent() throws {
        var event = lecture("Lecture every mon")
        event.apply(try #require(parse(event.title)), now: now, calendar: calendar)
        #expect(event.isEvent)
    }

    @Test func dayAndRangeMoveAnEvent() throws {
        var event = lecture("Dentist tomorrow 3-4pm")
        event.apply(try #require(parse(event.title)), now: now, calendar: calendar)

        #expect(event.title == "Dentist")
        #expect(event.start == at("2026-09-18", hour: 15))
        #expect(event.end == at("2026-09-18", hour: 16))
    }

    @Test func rangeEndingAfterMidnightEndsNextDay() throws {
        var event = lecture("Talk 10pm-1am")
        event.apply(try #require(parse(event.title)), now: now, calendar: calendar)

        #expect(event.start == at("2026-09-15", hour: 22))
        #expect(event.end == at("2026-09-16", hour: 1))
    }

    @Test func dayAloneKeepsAnEventsTime() throws {
        var event = lecture("Lecture friday")
        event.apply(try #require(parse(event.title)), now: now, calendar: calendar)

        #expect(event.title == "Lecture")
        #expect(event.start == at("2026-09-18", hour: 9))
        #expect(event.end == at("2026-09-18", hour: 10, minute: 15))
    }

    @Test func timeAloneKeepsAnEventsLength() throws {
        var event = lecture("Lecture 2pm")
        event.apply(try #require(parse(event.title)), now: now, calendar: calendar)

        #expect(event.start == at("2026-09-15", hour: 14))
        #expect(event.end == at("2026-09-15", hour: 15, minute: 15))
    }

    @Test func dayAloneSetsATasksDueDate() throws {
        var task = TaskItem(title: "Submit sep 22")
        task.apply(try #require(parse(task.title)), now: now, calendar: calendar)

        #expect(!task.isEvent)
        #expect(task.due == day("2026-09-22"))
    }

    @Test func ruleOnAnUndatedTaskStartsToday() throws {
        var task = TaskItem(title: "Stretch daily")
        task.apply(try #require(parse(task.title)), now: now, calendar: calendar)

        #expect(task.due == day("2026-09-17"))
        #expect(task.recurrence == Recurrence(frequency: .daily))
    }

    @Test func weekdayRuleMovesToTheNearestPickedDay() throws {
        var task = TaskItem(title: "Gym every mon wed")
        task.apply(try #require(parse(task.title)), now: now, calendar: calendar)
        #expect(task.due == day("2026-09-21"))

        var event = lecture("Gym every mon wed 7am")
        event.apply(try #require(parse(event.title)), now: now, calendar: calendar)
        #expect(event.start == at("2026-09-16", hour: 7))
        #expect(event.recurrence == Recurrence(frequency: .weekly, weekdays: [.mon, .wed]))
    }
}
