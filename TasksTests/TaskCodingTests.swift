import Foundation
import Testing
@testable import Tasks

struct TaskCodingTests {
    @Test func roundTripPreservesTasks() throws {
        let created = try #require(TaskDates.parse("2026-09-15T09:00:00Z"))
        let original = TaskFile(tasks: [
            TaskItem(
                title: "Finish ML assignment",
                notes: "Chapter 3 exercises",
                due: TaskDates.parse("2026-09-22"),
                createdAt: created
            ),
            TaskItem(title: "Buy notebook", done: true, createdAt: created),
        ])

        let decoded = try TaskFile.decode(original.encoded())

        #expect(decoded == original)
    }

    @Test func minimalTaskLoadsWithDefaults() throws {
        let file = try TaskFile.decode(Data(#"{"tasks":[{"title":"Buy milk"}]}"#.utf8))

        let task = try #require(file.tasks.first)
        #expect(file.version == TaskFile.currentVersion)
        #expect(task.title == "Buy milk")
        #expect(task.notes.isEmpty)
        #expect(task.done == false)
        #expect(task.due == nil)
    }

    @Test func emptyFileLoadsAsEmptyList() throws {
        #expect(try TaskFile.decode(Data()).tasks.isEmpty)
        #expect(try TaskFile.decode(Data("  \n".utf8)).tasks.isEmpty)
    }

    @Test func malformedJSONThrows() {
        #expect(throws: (any Error).self) {
            try TaskFile.decode(Data("{ not json".utf8))
        }
    }

    @Test func dueDateIsWrittenAsPlainDay() throws {
        let file = TaskFile(tasks: [
            TaskItem(title: "a", due: TaskDates.parse("2026-09-22"))
        ])

        let json = try JSONSerialization.jsonObject(with: file.encoded()) as? [String: Any]
        let tasks = try #require(json?["tasks"] as? [[String: Any]])

        #expect(tasks.first?["due"] as? String == "2026-09-22")
    }
}
