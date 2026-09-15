import Foundation
import Testing
@testable import Tasks

struct SubtaskTests {
    @Test(arguments: [
        ("- [ ] Q1", false, "Q1"),
        ("- [x] Q2 logistic", true, "Q2 logistic"),
        ("  - [X]  indented ", true, "indented"),
        ("- [ ]", false, ""),
    ])
    func checklistLinesParse(line: String, done: Bool, title: String) throws {
        let item = try #require(Checklist.parseLine(line))
        #expect(item.done == done)
        #expect(item.title == title)
    }

    @Test(arguments: ["Chapter 3", "- plain bullet", "[ ] no dash", "- [ ]no space", "- [y] other mark", ""])
    func otherLinesAreNotes(line: String) {
        #expect(Checklist.parseLine(line) == nil)
    }

    @Test func bareMarkerWaitsForSpaceWhileTyping() {
        #expect(Checklist.parseLine("- [ ]", whileTyping: true) == nil)
        #expect(Checklist.parseLine("- [ ] ", whileTyping: true)?.title == "")
    }

    @Test func extractKeepsNoteLinesInOrder() {
        let result = Checklist.extract(from: "Chapter 3\n- [x] Q1\nDue Friday\n- [ ] Q2")

        #expect(result.notes == "Chapter 3\nDue Friday")
        #expect(result.subtasks.map(\.title) == ["Q1", "Q2"])
        #expect(result.subtasks.map(\.done) == [true, false])
    }

    @Test func extractLeavesPlainNotesAlone() {
        let notes = "Chapter 3\n\n- bullet\n"
        let result = Checklist.extract(from: notes)

        #expect(result.notes == notes)
        #expect(result.subtasks.isEmpty)
    }

    @Test func subtasksRoundTrip() throws {
        let original = TaskFile(tasks: [
            TaskItem(
                title: "Finish ML assignment",
                notes: "Chapter 3",
                subtasks: [Subtask(title: "Q1", done: true), Subtask(title: "Q2")],
                createdAt: try #require(TaskDates.parse("2026-09-15T09:00:00Z"))
            ),
        ])

        #expect(try TaskFile.decode(original.encoded()) == original)
    }

    @Test func handWrittenSubtasksAndChecklistNotesLoad() throws {
        let json = #"{"tasks":[{"title":"a","notes":"Intro\n- [x] from notes","subtasks":[{"title":"listed"}]}]}"#
        let task = try #require(TaskFile.decode(Data(json.utf8)).tasks.first)

        #expect(task.notes == "Intro")
        #expect(task.subtasks.map(\.title) == ["listed", "from notes"])
        #expect(task.subtasks.map(\.done) == [false, true])
        #expect(task.subtaskProgress?.done == 1)
        #expect(task.subtaskProgress?.total == 2)
    }

    @Test func emptySubtasksAreNotWritten() throws {
        let json = try JSONSerialization.jsonObject(with: TaskFile(tasks: [TaskItem(title: "a")]).encoded())
        let tasks = try #require((json as? [String: Any])?["tasks"] as? [[String: Any]])

        #expect(tasks.first?["subtasks"] == nil)
    }

    @Test func searchFindsSubtaskTitles() {
        let tasks = [TaskItem(title: "Assignment", subtasks: [Subtask(title: "Logistic regression")])]

        #expect(SearchPalette.matchingTasks("logistic", in: tasks).map(\.title) == ["Assignment"])
    }
}
