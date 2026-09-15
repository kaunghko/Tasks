import SwiftUI

@main
struct TasksApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: TaskDocument()) { file in
            ContentView(document: file.$document)
        }
        .defaultSize(width: 960, height: 620)
    }
}
