import Foundation

/// A clock time without a day, such as 15:30.
struct TimeOfDay: Hashable, Comparable {
    var hour: Int
    var minute: Int = 0

    init(hour: Int, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }

    /// The local hour and minute of `date`.
    init(of date: Date, calendar: Calendar = .current) {
        self.init(hour: calendar.component(.hour, from: date), minute: calendar.component(.minute, from: date))
    }

    var minutes: Int { hour * 60 + minute }

    /// This time on the local day of `day`.
    func on(_ day: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.startOfDay(for: day))
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool { lhs.minutes < rhs.minutes }
}

/// A day, time or repeat rule found in a title, such as "tomorrow 3–4pm" or "every mon wed".
struct DetectedSchedule: Equatable {
    /// The matched words as typed, such as "every mon wed 7am". Separate matches are joined with " … ".
    var phrase: String
    /// The title without the matched words.
    var title: String
    /// Start of a local day.
    var day: Date?
    var start: TimeOfDay?
    /// With `start`, the end of a range such as "3–4pm". It can be earlier than the start
    /// ("10pm–1am"), which means the next day.
    var end: TimeOfDay?
    /// With `start`, a length such as "for 2 hours".
    var duration: TimeInterval?
    var recurrence: Recurrence?
    /// From "remind me 10 min before", "remind me" or "no reminder".
    var alert: TaskAlert?
}

/// Finds English dates, times and repeat rules in typed text. Suggestions only: nothing here
/// changes a task until the user applies the result (`TaskItem.apply`).
enum ScheduleParser {
    static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> DetectedSchedule? {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return nil }
        return Parser(text: text, tokens: tokens, now: now, calendar: calendar).run()
    }

    fileprivate struct Token {
        /// Lowercased word, digits, or a single symbol character.
        let text: String
        let range: Range<String.Index>
        /// No whitespace before it, as with "pm" in "3pm".
        let glued: Bool

        var number: Int? {
            guard text.count <= 4, text.allSatisfy(\.isASCIIDigit) else { return nil }
            return Int(text)
        }
    }

    fileprivate static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        var glued = false
        while index < text.endIndex {
            let character = text[index]
            if character.isWhitespace {
                glued = false
                index = text.index(after: index)
                continue
            }
            var end = text.index(after: index)
            if character.isLetter {
                while end < text.endIndex, text[end].isLetter { end = text.index(after: end) }
            } else if character.isASCIIDigit {
                while end < text.endIndex, text[end].isASCIIDigit { end = text.index(after: end) }
            }
            tokens.append(Token(text: text[index..<end].lowercased(), range: index..<end, glued: glued))
            glued = true
            index = end
        }
        return tokens
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

private struct Parser {
    let text: String
    let tokens: [ScheduleParser.Token]
    let now: Date
    let calendar: Calendar

    typealias Weekday = Recurrence.Weekday

    private enum Kind { case day, time, duration, recurrence, until, alert }

    // MARK: - Running

    func run() -> DetectedSchedule? {
        var day: Date?
        var start: TimeOfDay?
        var end: TimeOfDay?
        var duration: TimeInterval?
        var recurrence: Recurrence?
        var until: Date?
        var alert: TaskAlert?
        var tonight = false
        var spans: [(range: Range<Int>, kind: Kind)] = []

        var i = 0
        while i < tokens.count {
            // Alerts go first, so "10" in "remind me 10 min before" isn't a time.
            if alert == nil, let match = alertExpression(at: i) {
                alert = match.alert
                spans.append((i..<match.end, .alert))
                i = match.end
            } else if recurrence == nil, let match = repeatRule(at: i) {
                recurrence = match.rule
                if day == nil { day = match.day }
                spans.append((i..<match.end, .recurrence))
                i = match.end
            } else if until == nil, let match = untilDay(at: i) {
                until = match.day
                spans.append((i..<match.end, .until))
                i = match.end
            } else if day == nil, let match = dayExpression(at: i) {
                day = match.day
                tonight = match.tonight
                spans.append((i..<match.end, .day))
                i = match.end
            } else if start == nil, let match = timeExpression(at: i) {
                start = match.start
                end = match.end
                spans.append((i..<match.next, .time))
                i = match.next
            } else if duration == nil, let match = durationExpression(at: i) {
                duration = match.duration
                spans.append((i..<match.end, .duration))
                i = match.end
            } else {
                i += 1
            }
        }

        if tonight {
            // "tonight at 9" is 21:00.
            start = start.map { $0.hour < 12 ? TimeOfDay(hour: $0.hour + 12, minute: $0.minute) : $0 } ?? TimeOfDay(hour: 20)
            end = end.map { $0.hour < 12 && $0.hour > 0 ? TimeOfDay(hour: $0.hour + 12, minute: $0.minute) : $0 }
        }
        // A length or an end date means nothing on its own, so those words stay in the title.
        if start == nil || end != nil {
            duration = nil
            spans.removeAll { $0.kind == .duration }
        }
        if recurrence == nil {
            spans.removeAll { $0.kind == .until }
        } else if let until {
            recurrence?.until = until
        }
        guard !spans.isEmpty else { return nil }

        let ranges = spans.map(\.range).sorted { $0.lowerBound < $1.lowerBound }
        let title = remainingTitle(removing: ranges)
        guard !title.isEmpty else { return nil }
        return DetectedSchedule(
            phrase: phrase(of: ranges), title: title, day: day,
            start: start, end: start == nil ? nil : end, duration: duration, recurrence: recurrence,
            alert: alert
        )
    }

    private func stringRange(_ range: Range<Int>) -> Range<String.Index> {
        tokens[range.lowerBound].range.lowerBound..<tokens[range.upperBound - 1].range.upperBound
    }

    private func remainingTitle(removing ranges: [Range<Int>]) -> String {
        var parts: [Substring] = []
        var cursor = text.startIndex
        for range in ranges {
            let removed = stringRange(range)
            parts.append(text[cursor..<removed.lowerBound])
            cursor = removed.upperBound
        }
        parts.append(text[cursor...])

        var title = parts.joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .replacingOccurrences(of: " ,", with: ",")
        while title.contains(",,") {
            title = title.replacingOccurrences(of: ",,", with: ",")
        }
        return title.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—@"))
    }

    /// The matched words as typed. Matches with only spaces or commas between them read as one phrase.
    private func phrase(of ranges: [Range<Int>]) -> String {
        var groups: [Range<String.Index>] = []
        for range in ranges.map(stringRange) {
            if let last = groups.last,
               text[last.upperBound..<range.lowerBound].allSatisfy({ $0.isWhitespace || $0 == "," }) {
                groups[groups.count - 1] = last.lowerBound..<range.upperBound
            } else {
                groups.append(range)
            }
        }
        return groups.map { String(text[$0]) }.joined(separator: " … ")
    }

    // MARK: - Tokens

    private func word(_ i: Int) -> String? {
        i < tokens.count ? tokens[i].text : nil
    }

    private func isWord(_ i: Int, _ words: Set<String>) -> Bool {
        word(i).map(words.contains) ?? false
    }

    private func number(_ i: Int) -> Int? {
        i < tokens.count ? tokens[i].number : nil
    }

    private func isGlued(_ i: Int) -> Bool {
        i < tokens.count && tokens[i].glued
    }

    private var today: Date { calendar.startOfDay(for: now) }

    private func adding(_ component: Calendar.Component, _ value: Int, to date: Date) -> Date? {
        calendar.date(byAdding: component, value: value, to: date).map(calendar.startOfDay)
    }

    // MARK: - Days

    private static let fullWeekdays: [String: Weekday] = [
        "sunday": .sun, "monday": .mon, "tuesday": .tue, "wednesday": .wed,
        "thursday": .thu, "friday": .fri, "saturday": .sat,
    ]

    private static let shortWeekdays: [String: Weekday] = [
        "sun": .sun, "mon": .mon, "tue": .tue, "tues": .tue, "wed": .wed, "weds": .wed,
        "thu": .thu, "thur": .thu, "thurs": .thu, "fri": .fri, "sat": .sat,
    ]

    private static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4, "april": 4,
        "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10, "nov": 11, "november": 11,
        "dec": 12, "december": 12,
    ]

    /// A weekday name. Abbreviations like "sat" only count where a weekday is expected,
    /// so "sat exam" stays a title. Plurals ("mondays") only count when `plural` is set.
    private func weekday(_ i: Int, abbreviated: Bool, plural: Bool = false) -> Weekday? {
        guard let word = word(i) else { return nil }
        if let day = Self.fullWeekdays[word] { return day }
        if abbreviated, let day = Self.shortWeekdays[word] { return day }
        if plural, word.hasSuffix("s"), let day = Self.fullWeekdays[String(word.dropLast())] { return day }
        return nil
    }

    /// "today", "tomorrow", "on friday", "next week", "in 3 days", "sep 22", "due by 9/22"…
    private func dayExpression(at i: Int) -> (end: Int, day: Date, tonight: Bool)? {
        var j = i
        var prefixed = false
        if isWord(j, ["on", "by", "due"]) {
            j += 1
            prefixed = true
            if word(i) == "due", isWord(j, ["on", "by"]) {
                j += 1
            }
        }
        if word(j) == "tonight" {
            return (j + 1, today, true)
        }
        if let match = relativeDay(at: j, prefixed: prefixed) ?? absoluteDay(at: j) {
            return (match.end, match.day, false)
        }
        return nil
    }

    private func relativeDay(at i: Int, prefixed: Bool) -> (end: Int, day: Date)? {
        guard let first = word(i) else { return nil }
        switch first {
        case "today":
            return (i + 1, today)
        case "tomorrow", "tmr", "tmrw":
            return adding(.day, 1, to: today).map { (i + 1, $0) }
        case "day" where word(i + 1) == "after" && isWord(i + 2, ["tomorrow", "tmr", "tmrw"]):
            return adding(.day, 2, to: today).map { (i + 3, $0) }
        case "this":
            guard let weekday = weekday(i + 1, abbreviated: true) else { return nil }
            return (i + 2, next(weekday, includingToday: true))
        case "next":
            if let weekday = weekday(i + 1, abbreviated: true) {
                let nextWeek = adding(.day, 7, to: CalendarGrid.startOfWeek(containing: today, calendar: calendar))
                return nextWeek
                    .flatMap { adding(.day, weekday.offset(firstWeekday: calendar.firstWeekday), to: $0) }
                    .map { (i + 2, $0) }
            }
            if word(i + 1) == "week" {
                return adding(.day, 7, to: CalendarGrid.startOfWeek(containing: today, calendar: calendar))
                    .map { (i + 2, $0) }
            }
            if word(i + 1) == "month" {
                let month = calendar.dateInterval(of: .month, for: today)?.start ?? today
                return adding(.month, 1, to: month).map { (i + 2, $0) }
            }
            return nil
        case "in":
            guard let amount = number(i + 1) ?? (isWord(i + 1, ["a", "an"]) ? 1 : nil),
                  let unit = word(i + 2)
            else { return nil }
            let component: Calendar.Component? = switch unit {
            case "day", "days": .day
            case "week", "weeks": .weekOfYear
            case "month", "months": .month
            case "year", "years": .year
            default: nil
            }
            return component.flatMap { adding($0, amount, to: today) }.map { (i + 3, $0) }
        default:
            // Bare weekdays mean the next one; abbreviations need "on", "by" or "due" before them.
            guard let weekday = weekday(i, abbreviated: prefixed) else { return nil }
            return (i + 1, next(weekday, includingToday: false))
        }
    }

    private func next(_ weekday: Weekday, includingToday: Bool) -> Date {
        let current = Weekday(of: today, calendar: calendar)
        var days = (weekday.rawValue - current.rawValue + 7) % 7
        if days == 0, !includingToday {
            days = 7
        }
        return adding(.day, days, to: today) ?? today
    }

    /// "2026-09-22", "sep 22", "september 22nd, 2027", "22 sep", "22nd of september", "9/22".
    private func absoluteDay(at i: Int) -> (end: Int, day: Date)? {
        // ISO: 2026-09-22
        if let year = number(i), tokens[i].text.count == 4, word(i + 1) == "-", isGlued(i + 1),
           let month = number(i + 2), word(i + 3) == "-", let day = number(i + 4),
           let date = makeDay(year: year, month: month, day: day) {
            return (i + 5, date)
        }
        // sep 22[nd][, 2027]
        if let month = word(i).flatMap({ Self.months[$0] }), let day = number(i + 1) {
            var j = ordinalEnd(after: i + 1)
            let year = self.year(at: &j)
            return makeDay(year: year, month: month, day: day).map { (j, $0) }
        }
        // 22[nd] [of] sep[, 2027]
        if let day = number(i) {
            var j = ordinalEnd(after: i)
            if word(j) == "of" { j += 1 }
            if let month = word(j).flatMap({ Self.months[$0] }) {
                j += 1
                let year = self.year(at: &j)
                return makeDay(year: year, month: month, day: day).map { (j, $0) }
            }
        }
        // 9/22 or 22/9, in the locale's order, with an optional year.
        if let first = number(i), word(i + 1) == "/", let second = number(i + 2),
           isGlued(i + 1), isGlued(i + 2) {
            var end = i + 3
            var year: Int?
            if word(end) == "/", isGlued(end), let value = number(end + 1) {
                year = value < 100 ? 2000 + value : value
                end += 2
            }
            let (month, day) = dayComesFirst ? (second, first) : (first, second)
            return makeDay(year: year, month: month, day: day).map { (end, $0) }
        }
        return nil
    }

    private var dayComesFirst: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: calendar.locale ?? .current) ?? "M/d"
        guard let d = format.firstIndex(of: "d"), let m = format.firstIndex(of: "M") else { return false }
        return d < m
    }

    /// Skips an ordinal suffix glued to the number at `i`, as in "22nd".
    private func ordinalEnd(after i: Int) -> Int {
        isWord(i + 1, ["st", "nd", "rd", "th"]) && isGlued(i + 1) ? i + 2 : i + 1
    }

    /// An optional ", 2027" at `j`, moving `j` past it.
    private func year(at j: inout Int) -> Int? {
        let k = word(j) == "," ? j + 1 : j
        guard let year = number(k), tokens[k].text.count == 4 else { return nil }
        j = k + 1
        return year
    }

    /// A real calendar day. Without a year, a day that has passed means next year's.
    private func makeDay(year: Int?, month: Int, day: Int) -> Date? {
        func make(_ year: Int) -> Date? {
            let components = DateComponents(year: year, month: month, day: day)
            guard let date = calendar.date(from: components) else { return nil }
            let check = calendar.dateComponents([.year, .month, .day], from: date)
            return check.year == year && check.month == month && check.day == day ? date : nil
        }
        if let year {
            return make(year)
        }
        let thisYear = calendar.component(.year, from: today)
        if let date = make(thisYear), date >= today {
            return date
        }
        return make(thisYear + 1)
    }

    // MARK: - Times

    private struct Clock {
        var hour: Int
        var minute = 0
        var meridiem: String?
        /// Written like "15:00" or "noon", so it's a time even without am/pm.
        var isExplicit: Bool
        var leadingZero = false

        /// Without am/pm, 1 to 6 o'clock means the afternoon unless written like "05:00".
        var resolved: TimeOfDay {
            if let meridiem {
                return TimeOfDay(hour: hour % 12 + (meridiem == "pm" ? 12 : 0), minute: minute)
            }
            if !leadingZero, (1...6).contains(hour) {
                return TimeOfDay(hour: hour + 12, minute: minute)
            }
            return TimeOfDay(hour: hour, minute: minute)
        }
    }

    private func clock(at i: Int) -> (end: Int, clock: Clock)? {
        if word(i) == "noon" { return (i + 1, Clock(hour: 12, meridiem: "pm", isExplicit: true)) }
        if word(i) == "midnight" { return (i + 1, Clock(hour: 12, meridiem: "am", isExplicit: true)) }
        guard let hour = number(i), tokens[i].text.count <= 2 else { return nil }
        var clock = Clock(hour: hour, isExplicit: false, leadingZero: tokens[i].text.count == 2 && tokens[i].text.hasPrefix("0"))
        var j = i + 1
        if word(j) == ":", isGlued(j), isGlued(j + 1), let minute = number(j + 1),
           tokens[j + 1].text.count == 2, minute < 60 {
            clock.minute = minute
            clock.isExplicit = true
            j += 2
        }
        if isWord(j, ["am", "pm"]) {
            clock.meridiem = word(j)
            clock.isExplicit = true
            j += 1
        }
        let valid = clock.meridiem == nil ? (0...23).contains(hour) : (1...12).contains(hour)
        return valid ? (j, clock) : nil
    }

    /// "3pm", "at 15:30", "noon", "3-4pm", "from 9:00 to 10:15". A bare number needs "at" or "from".
    private func timeExpression(at i: Int) -> (next: Int, start: TimeOfDay, end: TimeOfDay?)? {
        var j = i
        let prefixed = isWord(j, ["at", "by", "from", "@"])
        if prefixed { j += 1 }
        guard let (afterStart, start) = clock(at: j) else { return nil }

        if isWord(afterStart, ["-", "–", "—", "to"]), let (afterEnd, end) = clock(at: afterStart + 1),
           start.isExplicit || end.isExplicit || prefixed {
            var first = start
            // "3-4pm" and "11-1pm": the start takes the end's am/pm unless that puts it after the end.
            if first.meridiem == nil, let meridiem = end.meridiem, (1...12).contains(first.hour) {
                first.meridiem = meridiem
                if first.resolved > end.resolved, meridiem == "pm" {
                    first.meridiem = "am"
                }
            }
            return (afterEnd, first.resolved, end.resolved)
        }
        guard start.isExplicit || prefixed else { return nil }
        return (afterStart, start.resolved, nil)
    }

    // MARK: - Alerts

    /// "remind me 10 min before", "notify 1h before", "alert me the day before", "remind me",
    /// "no reminder", "don't remind me". Only offsets before the time; "after" isn't matched.
    private func alertExpression(at i: Int) -> (end: Int, alert: TaskAlert)? {
        if word(i) == "no", isWord(i + 1, ["reminder", "reminders", "alert", "alerts", "notification", "notifications"]) {
            return (i + 2, .none)
        }
        if isWord(i, ["don", "dont"]) {
            var j = i + 1
            if isWord(j, ["'", "’"]), word(j + 1) == "t" { j += 2 }
            guard word(j) == "remind" else { return nil }
            j += 1
            if word(j) == "me" { j += 1 }
            return (j, .none)
        }

        guard let keyword = word(i), ["remind", "alert", "notify"].contains(keyword) else { return nil }
        var j = i + 1
        if word(j) == "me" { j += 1 }
        if let offset = alertOffset(at: j) {
            return (offset.end, offset.minutes > 0 ? .minutesBefore(offset.minutes) : .atTime)
        }

        // "alert" and "notify" alone are too often just words in a title ("fix alert bug").
        // "Remind me to call mom" is a title, and "remind me 10 min after" isn't supported.
        guard keyword == "remind",
              !isWord(j, ["to", "about", "that", "of", "a", "an", "the"]), number(j) == nil
        else { return nil }
        if word(j) == "at", word(j + 1) == "the", word(j + 2) == "time" {
            j += 3
        } else if word(j) == "on", word(j + 1) == "time" {
            j += 2
        }
        return (j, .atTime)
    }

    /// "10 min before", "an hour before", "1 hour and 30 min before", "2 days early", "the day before".
    private func alertOffset(at i: Int) -> (end: Int, minutes: Int)? {
        if word(i) == "the", word(i + 1) == "day", word(i + 2) == "before" {
            return (i + 3, 24 * 60)
        }
        var j = i
        var total = 0
        while true {
            let amount: Int
            if let value = number(j) {
                amount = value
            } else if total == 0, isWord(j, ["a", "an"]) {
                amount = 1
            } else {
                break
            }
            let unit: Int? = switch word(j + 1) {
            case "m", "min", "mins", "minute", "minutes": 1
            case "h", "hr", "hrs", "hour", "hours": 60
            case "d", "day", "days": 24 * 60
            case "w", "wk", "wks", "week", "weeks": 7 * 24 * 60
            default: nil
            }
            guard let unit else { return nil }
            total += amount * unit
            j += 2
            if word(j) == "and", number(j + 1) != nil || isWord(j + 1, ["a", "an"]) { j += 1 }
        }
        guard j > i, isWord(j, ["before", "early"]) else { return nil }
        return (j + 1, total)
    }

    /// "for 2 hours", "for 30 min", "for 1h30m", "for an hour", "for half an hour", "for 1.5 hours".
    private func durationExpression(at i: Int) -> (end: Int, duration: TimeInterval)? {
        guard word(i) == "for" else { return nil }
        var j = i + 1
        if word(j) == "half", isWord(j + 1, ["an", "a"]), word(j + 2) == "hour" {
            return (j + 3, 1800)
        }
        var total: TimeInterval = 0
        while true {
            var amount: Double
            if let value = number(j) {
                amount = Double(value)
                j += 1
                if word(j) == ".", isGlued(j), number(j + 1) != nil, isGlued(j + 1) {
                    amount = Double("\(value).\(tokens[j + 1].text)") ?? amount
                    j += 2
                }
            } else if total == 0, isWord(j, ["an", "a"]) {
                amount = 1
                j += 1
            } else {
                break
            }
            let unit: TimeInterval? = switch word(j) {
            case "h", "hr", "hrs", "hour", "hours": 3600
            case "m", "min", "mins", "minute", "minutes": 60
            default: nil
            }
            guard let unit else { return nil }
            total += amount * unit
            j += 1
            if word(j) == "and", number(j + 1) != nil { j += 1 }
        }
        return total > 0 ? (j, total) : nil
    }

    // MARK: - Repeat rules

    /// "daily", "every other week", "every mon, wed and fri", "on mondays", "every month on the 1st",
    /// "every 15th", "yearly on sep 22", "every sep 22".
    private func repeatRule(at i: Int) -> (end: Int, rule: Recurrence, day: Date?)? {
        guard let first = word(i) else { return nil }
        switch first {
        case "daily":
            return (i + 1, Recurrence(frequency: .daily), nil)
        case "weekly":
            return weekly(interval: 1, after: i + 1)
        case "monthly":
            return monthly(interval: 1, after: i + 1)
        case "yearly", "annually":
            return yearly(interval: 1, after: i + 1)
        case "on":
            // "on mondays" repeats; "on monday" is just a day.
            guard let (end, days) = weekdayList(at: i + 1, plural: true),
                  (i + 1..<end).contains(where: isPluralWeekday)
            else { return nil }
            return (end, Recurrence(frequency: .weekly, weekdays: days), nil)
        case "every", "each":
            break
        default:
            return nil
        }

        var j = i + 1
        var interval = 1
        if word(j) == "other" {
            interval = 2
            j += 1
        } else if let value = number(j), !isWord(j + 1, ["st", "nd", "rd", "th"]) || !isGlued(j + 1),
                  value > 0, value < 100 {
            interval = value
            j += 1
        }

        switch word(j) {
        case "day", "days":
            return (j + 1, Recurrence(frequency: .daily, interval: interval), nil)
        case "week", "weeks":
            return weekly(interval: interval, after: j + 1)
        case "month", "months":
            return monthly(interval: interval, after: j + 1)
        case "year", "years":
            return yearly(interval: interval, after: j + 1)
        case "weekday" where interval == 1:
            return (j + 1, Recurrence(frequency: .weekly, weekdays: [.mon, .tue, .wed, .thu, .fri]), nil)
        case "weekend" where interval == 1:
            return (j + 1, Recurrence(frequency: .weekly, weekdays: [.sat, .sun]), nil)
        default:
            break
        }
        if let (end, days) = weekdayList(at: j, plural: true) {
            return (end, Recurrence(frequency: .weekly, interval: interval, weekdays: days), nil)
        }
        guard j == i + 1 else { return nil }
        if let (end, day) = monthDay(at: j) {
            var k = end
            if word(k) == "of", word(k + 1) == "the", word(k + 2) == "month" { k += 3 }
            return (k, Recurrence(frequency: .monthly), day)
        }
        if word(j).flatMap({ Self.months[$0] }) != nil, let (end, day) = absoluteDay(at: j) {
            return (end, Recurrence(frequency: .yearly), day)
        }
        return nil
    }

    private func weekly(interval: Int, after i: Int) -> (end: Int, rule: Recurrence, day: Date?) {
        if word(i) == "on", let (end, days) = weekdayList(at: i + 1, plural: true) {
            return (end, Recurrence(frequency: .weekly, interval: interval, weekdays: days), nil)
        }
        return (i, Recurrence(frequency: .weekly, interval: interval), nil)
    }

    private func monthly(interval: Int, after i: Int) -> (end: Int, rule: Recurrence, day: Date?) {
        var j = i
        if word(j) == "on" { j += 1 }
        if word(j) == "the" { j += 1 }
        if j > i, let (end, day) = monthDay(at: j) {
            return (end, Recurrence(frequency: .monthly, interval: interval), day)
        }
        return (i, Recurrence(frequency: .monthly, interval: interval), nil)
    }

    private func yearly(interval: Int, after i: Int) -> (end: Int, rule: Recurrence, day: Date?) {
        if word(i) == "on", let (end, day) = absoluteDay(at: i + 1) {
            return (end, Recurrence(frequency: .yearly, interval: interval), day)
        }
        return (i, Recurrence(frequency: .yearly, interval: interval), nil)
    }

    private func isPluralWeekday(_ i: Int) -> Bool {
        guard let word = word(i), word.hasSuffix("s") else { return false }
        return Self.fullWeekdays[String(word.dropLast())] != nil
    }

    /// "mon wed", "monday, wednesday and friday", "mondays & fridays".
    private func weekdayList(at i: Int, plural: Bool) -> (end: Int, days: Set<Weekday>)? {
        var days: Set<Weekday> = []
        var j = i
        while let day = weekday(j, abbreviated: true, plural: plural) {
            days.insert(day)
            j += 1
            var k = j
            while isWord(k, [",", "and", "&"]) { k += 1 }
            guard k > j, weekday(k, abbreviated: true, plural: plural) != nil else { continue }
            j = k
        }
        return days.isEmpty ? nil : (j, days)
    }

    /// An ordinal like "15th": the next day of the month with that number, today included.
    private func monthDay(at i: Int) -> (end: Int, day: Date)? {
        guard let value = number(i), (1...31).contains(value),
              isWord(i + 1, ["st", "nd", "rd", "th"]), isGlued(i + 1)
        else { return nil }
        let components = calendar.dateComponents([.year, .month], from: today)
        for offset in 0..<12 {
            guard let month = calendar.date(from: components).flatMap({ adding(.month, offset, to: $0) }) else { continue }
            let parts = calendar.dateComponents([.year, .month], from: month)
            if let day = parts.year.flatMap({ makeDay(year: $0, month: parts.month ?? 1, day: value) }), day >= today {
                return (i + 2, day)
            }
        }
        return nil
    }

    /// "until dec 17", "through 12/17", "till next month".
    private func untilDay(at i: Int) -> (end: Int, day: Date)? {
        guard isWord(i, ["until", "till", "til", "through", "thru"]) else { return nil }
        return relativeDay(at: i + 1, prefixed: true) ?? absoluteDay(at: i + 1)
    }
}
