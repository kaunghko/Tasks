import Foundation

/// The top-level shape of a tasks `.json` file.
struct TaskFile: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var tasks: [TaskItem]

    init(version: Int = TaskFile.currentVersion, tasks: [TaskItem] = []) {
        self.version = version
        self.tasks = tasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? TaskFile.currentVersion
        tasks = try container.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
    }

    /// Decodes a file's contents. An empty or whitespace-only file is an empty task list.
    static func decode(_ data: Data) throws -> TaskFile {
        let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
        if data.allSatisfy(whitespace.contains) {
            return TaskFile()
        }
        return try JSONDecoder().decode(TaskFile.self, from: data)
    }

    /// Pretty-printed with sorted keys so hand edits and git diffs stay readable.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}
