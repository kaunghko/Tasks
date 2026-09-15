import Foundation

/// A checklist item inside a task. Typed into notes as `- [ ] title`, stored in JSON as its own array.
struct Subtask: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var done: Bool

    init(id: UUID = UUID(), title: String = "", done: Bool = false) {
        self.id = id
        self.title = title
        self.done = done
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, done
    }

    /// Tolerant decoding, like `TaskItem`: `{"title": "Q1"}` is a valid subtask.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID(),
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
            done: try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
        )
    }
}

extension Array where Element == Subtask {
    /// Looks a subtask up by id. A row's binding by index would read past the end
    /// after a subtask above it is deleted, and crash.
    subscript(id id: Subtask.ID) -> Subtask {
        get { first { $0.id == id } ?? Subtask(id: id) }
        set {
            guard let index = firstIndex(where: { $0.id == id }) else { return }
            self[index] = newValue
        }
    }
}

/// Markdown-style checklist lines (`- [ ] open`, `- [x] done`) in task notes.
enum Checklist {
    /// Reads one line. `whileTyping` skips a bare `- [ ]` with nothing after it yet,
    /// so the space the user is about to type doesn't land in the new subtask's title.
    static func parseLine<S: StringProtocol>(_ line: S, whileTyping: Bool = false) -> (done: Bool, title: String)?
    where S.SubSequence == Substring {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        let marker = Array(trimmed.prefix(5))
        guard marker.count == 5, marker[0] == "-", marker[1] == " ", marker[2] == "[", marker[4] == "]" else {
            return nil
        }
        let done: Bool
        switch marker[3] {
        case " ": done = false
        case "x", "X": done = true
        default: return nil
        }
        let rest = trimmed.dropFirst(5)
        if rest.isEmpty {
            return whileTyping ? nil : (done, "")
        }
        guard rest.first == " " else { return nil }
        return (done, rest.dropFirst().trimmingCharacters(in: .whitespaces))
    }

    /// Moves checklist lines out of `notes` into subtasks, keeping the other lines in order.
    static func extract(from notes: String, whileTyping: Bool = false) -> (notes: String, subtasks: [Subtask]) {
        var kept: [Substring] = []
        var subtasks: [Subtask] = []
        for line in notes.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if let item = parseLine(line, whileTyping: whileTyping) {
                subtasks.append(Subtask(title: item.title, done: item.done))
            } else {
                kept.append(line)
            }
        }
        guard !subtasks.isEmpty else { return (notes, []) }
        return (kept.joined(separator: "\n").trimmingCharacters(in: .newlines), subtasks)
    }
}
