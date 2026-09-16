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

    @Test func eventRoundTripsWithLocalOffsetTimes() throws {
        let start = try #require(TaskDates.parse("2026-09-22T09:00:00+09:00"))
        let end = try #require(TaskDates.parse("2026-09-22T10:15:00+09:00"))
        let created = try #require(TaskDates.parse("2026-09-15T09:00:00Z"))
        let original = TaskFile(tasks: [TaskItem(title: "ML lecture", start: start, end: end, createdAt: created)])

        let data = try original.encoded()
        #expect(try TaskFile.decode(data) == original)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let event = try #require((json?["tasks"] as? [[String: Any]])?.first)
        #expect(event["due"] == nil)
        #expect(event["done"] == nil)
        #expect(event["start"] as? String == TaskDates.localTimestampString(start))
        #expect(event["end"] as? String == TaskDates.localTimestampString(end))
        #expect(TaskDates.parse(event["start"] as? String ?? "") == start)
    }

    @Test(arguments: [nil, "not a date", "2026-09-22T08:00:00Z"])
    func eventWithoutValidEndLastsAnHour(end: String?) throws {
        let endField = end.map { #", "end": "\#($0)""# } ?? ""
        let json = #"{"tasks": [{"title": "Call", "start": "2026-09-22T09:00:00Z"\#(endField)}]}"#
        let event = try #require(try TaskFile.decode(Data(json.utf8)).tasks.first)

        #expect(event.isEvent)
        #expect(event.end == TaskDates.parse("2026-09-22T10:00:00Z"))
        #expect(event.due == Calendar.current.startOfDay(for: event.start!))
        #expect(event.done == false)
    }

    @Test func unparseableStartLoadsAsTask() throws {
        let json = #"{"tasks": [{"title": "a", "start": "soon", "due": "2026-09-22", "done": true}]}"#
        let task = try #require(try TaskFile.decode(Data(json.utf8)).tasks.first)

        #expect(!task.isEvent)
        #expect(task.done)
        #expect(task.due == TaskDates.parse("2026-09-22"))
    }

    @Test func plainTaskEncodesWithoutEventFields() throws {
        let json = """
        {
          "tasks" : [
            {
              "createdAt" : "2026-09-15T09:00:00Z",
              "done" : false,
              "due" : "2026-09-22",
              "id" : "0B7E6C2A-7D0F-4C8E-9B61-2F6A1E3C4D01",
              "notes" : "",
              "title" : "Buy milk"
            }
          ],
          "version" : 1
        }

        """
        #expect(try String(decoding: TaskFile.decode(Data(json.utf8)).encoded(), as: UTF8.self) == json)
    }
}
