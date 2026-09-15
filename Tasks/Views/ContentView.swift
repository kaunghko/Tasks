import AppKit
import SwiftUI

struct ContentView: View {
    @Binding var document: TaskDocument

    @State private var destination: AppDestination? = .filter(.all)
    @State private var selection: Set<TaskItem.ID> = []
    /// The task whose details popover is open.
    @State private var detailTaskID: TaskItem.ID?
    @State private var isPaletteShown = false
    @State private var calendarDate = Date.now
    @SceneStorage("calendarMode") private var calendarMode: CalendarMode = .month
    /// A task the list should scroll to and then open details for.
    @State private var revealID: TaskItem.ID?

    private var currentFilter: TaskFilter {
        switch destination {
        case .filter(let filter): filter
        default: .all
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $destination) {
                Section {
                    ForEach(TaskFilter.allCases) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .badge(item.apply(to: document.file.tasks).count)
                            .tag(AppDestination.filter(item))
                    }
                }
                Section {
                    Label("Calendar", systemImage: "calendar")
                        .tag(AppDestination.calendar)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200)
        } detail: {
            detail
                .onDeleteCommand { delete(selection) }
                .onKeyPress(.space) {
                    guard !selection.isEmpty else { return .ignored }
                    toggleDone(selection)
                    return .handled
                }
                .navigationTitle(destination == .calendar ? "Calendar" : currentFilter.title)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New Task", systemImage: "plus", action: addTask)
                            .keyboardShortcut("n", modifiers: [.command, .shift])
                    }
                    ToolbarItem {
                        Button("Search", systemImage: "magnifyingglass") {
                            isPaletteShown.toggle()
                        }
                        .keyboardShortcut("k", modifiers: .command)
                        .help("Search tasks and views (⌘K)")
                    }
                }
        }
        .overlay {
            if isPaletteShown {
                SearchPaletteView(
                    tasks: document.file.tasks,
                    onChoose: choose,
                    onDismiss: { isPaletteShown = false }
                )
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if destination == .calendar {
            CalendarView(
                tasks: $document.file.tasks,
                selection: $selection,
                visibleDate: $calendarDate,
                mode: $calendarMode,
                detailTaskID: $detailTaskID,
                onAdd: insertTask(due:),
                onReschedule: reschedule,
                onToggleDone: toggleDone,
                onDelete: delete
            )
        } else {
            taskList
        }
    }

    // MARK: - Task list

    private var taskList: some View {
        let tasks = currentFilter.apply(to: document.file.tasks)
        return ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(tasks) { task in
                    TaskRow(task: $document.file.tasks[id: task.id])
                        .contentShape(.rect)
                        // Simultaneous, so the List still handles selection and ⌘/⇧-clicks.
                        .simultaneousGesture(TapGesture().onEnded {
                            if !NSEvent.modifierFlags.contains(.command), !NSEvent.modifierFlags.contains(.shift) {
                                detailTaskID = task.id
                            }
                        })
                        .popover(isPresented: detailsShown(task.id), arrowEdge: .trailing) {
                            TaskDetailView(task: $document.file.tasks[id: task.id])
                        }
                        .contextMenu {
                            Button(task.done ? "Mark as Not Done" : "Mark as Done") {
                                toggleDone([task.id])
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                delete([task.id])
                            }
                        }
                }
            }
            .task(id: revealID) {
                guard let id = revealID else { return }
                await Task.yield()
                proxy.scrollTo(id, anchor: .center)
                // Let the row settle on screen before a popover attaches to it.
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                detailTaskID = id
                revealID = nil
            }
            .onChange(of: selection) { _, newValue in
                // Backs up the tap gesture: a plain click that selects one task opens its details.
                // Programmatic selections (new task, palette) go through `revealID` instead.
                guard revealID == nil, newValue.count == 1, let id = newValue.first,
                      let event = NSApp.currentEvent,
                      event.type == .leftMouseDown || event.type == .leftMouseUp,
                      event.modifierFlags.isDisjoint(with: [.command, .shift])
                else { return }
                detailTaskID = id
            }
        }
        .overlay {
            if tasks.isEmpty {
                ContentUnavailableView(
                    "No Tasks",
                    systemImage: currentFilter.systemImage,
                    description: Text("Press ⇧⌘N to add a task.")
                )
            }
        }
    }

    private func detailsShown(_ id: TaskItem.ID) -> Binding<Bool> {
        Binding(
            get: { detailTaskID == id },
            set: { isShown in
                if !isShown, detailTaskID == id {
                    detailTaskID = nil
                }
            }
        )
    }

    /// Opens a task's popover once its row or chip is on screen.
    private func openDetails(_ id: TaskItem.ID) {
        if destination == .calendar {
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                detailTaskID = id
            }
        } else {
            revealID = id
        }
    }

    // MARK: - Actions
    // Each action assigns to `document` once, so it becomes a single undo step.

    /// Opens a view, or selects a task where it can be seen and opens its details.
    private func choose(_ result: PaletteResult) {
        isPaletteShown = false
        switch result {
        case .view(let view):
            destination = view.destination
            if let mode = view.calendarMode {
                calendarMode = mode
            }
        case .task(let task):
            switch destination {
            case .calendar:
                // An undated task has no chip to attach the popover to, so show it in All.
                if let due = task.due {
                    calendarDate = due
                } else {
                    destination = .filter(.all)
                }
            case .filter(let filter) where filter.includes(task):
                break
            default:
                destination = .filter(.all)
            }
            selection = [task.id]
            openDetails(task.id)
        }
    }

    /// New Task from the toolbar: the due date follows what's on screen.
    private func addTask() {
        switch destination {
        case .filter(.today):
            insertTask(due: .now)
        case .filter(.upcoming):
            insertTask(due: Calendar.current.date(byAdding: .day, value: 1, to: .now))
        case .filter(.completed):
            destination = .filter(.all)
            insertTask(due: nil)
        case .calendar:
            insertTask(due: calendarDate)
        default:
            insertTask(due: nil)
        }
    }

    private func insertTask(due: Date?) {
        let task = TaskItem(title: "New Task", due: due)
        document.file.tasks.append(task)
        selection = [task.id]
        openDetails(task.id)
    }

    private func delete(_ ids: Set<TaskItem.ID>) {
        guard !ids.isEmpty else { return }
        if let detailTaskID, ids.contains(detailTaskID) {
            self.detailTaskID = nil
        }
        document.file.tasks.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    /// Marks all as done if any are open; otherwise reopens them.
    private func toggleDone(_ ids: Set<TaskItem.ID>) {
        var tasks = document.file.tasks
        let markDone = tasks.contains { ids.contains($0.id) && !$0.done }
        for index in tasks.indices where ids.contains(tasks[index].id) {
            tasks[index].done = markDone
        }
        document.file.tasks = tasks
    }

    /// Moves tasks to a day, or clears their due date when `day` is nil.
    private func reschedule(_ ids: Set<TaskItem.ID>, to day: Date?) {
        var tasks = document.file.tasks
        for index in tasks.indices where ids.contains(tasks[index].id) {
            tasks[index].due = day.map { Calendar.current.startOfDay(for: $0) }
        }
        guard tasks != document.file.tasks else { return }
        document.file.tasks = tasks
    }
}
