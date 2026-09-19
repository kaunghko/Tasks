import Sparkle
import SwiftUI

@main
struct TasksApp: App {
    /// Checks the appcast in `SUFeedURL` (Tasks-Info.plist) once a day and installs signed updates.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    init() {
        NotificationScheduler.shared.start()
    }

    var body: some Scene {
        DocumentGroup(newDocument: TaskDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 960, height: 620)
        .commands {
            // ⌘N adds a task (ContentView's toolbar), so a new window moves to ⇧⌘N.
            CommandGroup(replacing: .newItem) {
                NewWindowButton()
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}

/// File > New Window: a new untitled task file in its own window.
private struct NewWindowButton: View {
    @Environment(\.newDocument) private var newDocument

    var body: some View {
        Button("New Window") { newDocument(TaskDocument()) }
            .keyboardShortcut("n", modifiers: [.command, .shift])
    }
}
