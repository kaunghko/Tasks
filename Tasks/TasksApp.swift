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
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}
