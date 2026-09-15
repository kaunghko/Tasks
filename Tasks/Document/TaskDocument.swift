import SwiftUI
import UniformTypeIdentifiers

/// A task list backed by a plain `.json` file. The file is the source of truth;
/// `DocumentGroup` provides open, autosave, undo and versions on top of it.
struct TaskDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var file: TaskFile

    init(file: TaskFile = TaskFile()) {
        self.file = file
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        do {
            file = try TaskFile.decode(data)
        } catch {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try file.encoded())
    }
}
