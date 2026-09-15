import SwiftUI

struct ContentView: View {
    @Binding var document: TaskDocument

    @State private var destination: AppDestination? = .filter(.all)
    @State private var selection: Set<TaskItem.ID> = []
    @State private var isInspectorPresented = true
    @State private var isPaletteShown = false
    @State private var calendarDate = Date.now
    @SceneStorage("calendarMode") private var calendarMode: CalendarMode = .month
    /// A task chosen in the palette that the list should scroll to.
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
                    ToolbarItem {
                        Button("Inspector", systemImage: "sidebar.trailing") {
                            isInspectorPresented.toggle()
                        }
                    }
                }
                .inspector(isPresented: $isInspectorPresented) {
                    inspector
                        .inspectorColumnWidth(min: 240, ideal: 280)
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
                revealID = nil
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

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        if selection.count == 1, let id = selection.first,
           document.file.tasks.contains(where: { $0.id == id }) {
            TaskInspector(task: $document.file.tasks[id: id])
        } else {
            ContentUnavailableView(
                selection.isEmpty ? "No Selection" : "\(selection.count) Tasks Selected",
                systemImage: "checklist"
            )
        }
    }

    // MARK: - Actions
    // Each action assigns to `document` once, so it becomes a single undo step.

    /// Opens a view, or selects a task where it can be seen.
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
                if let due = task.due {
                    calendarDate = due
                }
            case .filter(let filter) where filter.includes(task):
                break
            default:
                destination = .filter(.all)
            }
            selection = [task.id]
            isInspectorPresented = true
            revealID = task.id
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
        isInspectorPresented = true
    }

    private func delete(_ ids: Set<TaskItem.ID>) {
        guard !ids.isEmpty else { return }
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
