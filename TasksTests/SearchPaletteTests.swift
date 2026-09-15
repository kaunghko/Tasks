import Foundation
import Testing
@testable import Tasks

private func day(_ string: String) -> Date {
    Calendar.current.startOfDay(for: TaskDates.parse(string)!)
}

private let now = day("2026-09-15").addingTimeInterval(10 * 3600)
private let reportDraft = TaskItem(title: "Report draft", due: day("2026-09-15"), createdAt: day("2026-09-01"))
private let writeReport = TaskItem(title: "Write report", due: day("2026-09-20"), createdAt: day("2026-09-02"))
private let shareNotes = TaskItem(title: "Share notes", createdAt: day("2026-09-03"))
private let buyMilk = TaskItem(title: "Buy milk", notes: "remember oat", createdAt: day("2026-09-04"))
private let weeklyReview = TaskItem(title: "Weekly review", createdAt: day("2026-09-05"))
private let sample = [buyMilk, shareNotes, writeReport, reportDraft, weeklyReview]

struct SearchPaletteTests {
    private func titles(_ text: String, scope: PaletteScope = .mixed) -> [String] {
        SearchPalette.results(for: .parse(text, lockedScope: scope), tasks: sample, now: now).map(\.title)
    }

    @Test func atPrefixSearchesViews() {
        #expect(PaletteQuery.parse("@wee") == PaletteQuery(scope: .views, term: "wee"))
        #expect(PaletteQuery.parse(" @ month ") == PaletteQuery(scope: .views, term: "month"))
    }

    @Test func lockedScopeTakesTextLiterally() {
        #expect(PaletteQuery.parse("@wee", lockedScope: .tasks) == PaletteQuery(scope: .tasks, term: "@wee"))
        #expect(PaletteQuery.parse("  milk ") == PaletteQuery(scope: .mixed, term: "milk"))
    }

    @Test(arguments: [("daily", "Today"), ("day", "Today"), ("week", "Week"), ("monthly", "Month"), ("done", "Completed")])
    func aliasesFindViews(term: String, view: String) {
        #expect(titles(term, scope: .views).first == view)
    }

    @Test func tasksRankByTitlePositionThenNotes() {
        #expect(titles("re", scope: .tasks) == ["Report draft", "Write report", "Weekly review", "Share notes", "Buy milk"])
    }

    @Test func scopesKeepResultsApart() {
        #expect(titles("week", scope: .tasks) == ["Weekly review"])
        #expect(titles("@week") == ["Week"])
        #expect(titles("week") == ["Week", "Weekly review"])
    }

    @Test func emptyMixedSearchSuggestsViewsAndTodaysTasks() {
        let expected = PaletteView.all.map(\.title) + ["Report draft"]
        #expect(titles("") == expected)
    }

    @Test func emptyTaskSearchListsAllTasks() {
        #expect(titles("", scope: .tasks).count == sample.count)
    }
}
