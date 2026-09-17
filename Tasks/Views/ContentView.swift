import AppKit
import SwiftUI

struct ContentView: View {
    @Binding var document: TaskDocument

    @State private var destination: AppDestination? = .filter(.all)
    @State private var selection: Set<TaskItem.ID> = []
    /// The task whose details popover is open.
    @State private var detailTaskID: TaskItem.ID?
    /// Set briefly while an item switches between task and event from its popover.
    @State private var kindSwitchID: TaskItem.ID?
    @State private var isPaletteShown = false
    /// The sidebar starts hidden so the task list opens uncluttered.
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
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

    /// The window title: the current view rather than the document's file name.
    private var viewTitle: String {
        destination == .calendar ? "Calendar" : currentFilter.title
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
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
                    // Space types a space while editing text, e.g. notes in the details popover.
                    guard !selection.isEmpty, !(NSApp.keyWindow?.firstResponder is NSText) else { return .ignored }
                    toggleDone(selection)
                    return .handled
                }
                .navigationTitle(viewTitle)
                .background(WindowTitle(title: viewTitle))
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New Task", systemImage: "plus", action: addTask)
                            .keyboardShortcut("n", modifiers: [.command, .shift])
                            .help("New task (⇧⌘N)")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("New Event", systemImage: "calendar.badge.plus", action: addEvent)
                            .keyboardShortcut("n", modifiers: [.command, .option])
                            .help("New event (⌥⌘N)")
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
        .environment(\.willSwitchKind, willSwitchKind)
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
                onAddEvent: insertEvent(start:end:),
                onReschedule: reschedule,
                onMove: move,
                onToggleDone: toggleDone,
                onDelete: delete,
                detailsShown: detailsShown
            )
        } else {
            taskList
        }
    }

    // MARK: - Task list

    private var taskList: some View {
        var tasks = currentFilter.apply(to: document.file.tasks)
        // Keep the task whose popover is open, so an edit that moves it out of this list
        // (marking it done in Today, switching it to an event) doesn't close the popover under the cursor.
        if let id = detailTaskID, !tasks.contains(where: { $0.id == id }),
           let open = document.file.tasks.first(where: { $0.id == id }) {
            tasks.append(open.currentOccurrence())
            tasks.sort(by: TaskFilter.displayOrder)
        }
        return ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(tasks) { task in
                    TaskRow(task: $document.file.tasks[id: task.id], occurrence: task)
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
                            if !task.isEvent {
                                Button(task.done ? "Mark as Not Done" : "Mark as Done") {
                                    toggleDone([task.id])
                                }
                                Divider()
                            }
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
            .background {
                // ⌘1–⌘9 select the task at that position. The Calendar uses ⌘1/⌘2 for Month/Week instead.
                ForEach(1...9, id: \.self) { number in
                    Button("Select Task \(number)") { selectTask(at: number - 1, in: tasks, proxy: proxy) }
                        .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                }
                .opacity(0)
                .accessibilityHidden(true)
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

    /// ⌘1–⌘9: selects the task at that position in the list and scrolls to it.
    private func selectTask(at index: Int, in tasks: [TaskItem], proxy: ScrollViewProxy) {
        guard tasks.indices.contains(index) else { return }
        selection = [tasks[index].id]
        proxy.scrollTo(tasks[index].id)
    }

    private func detailsShown(_ id: TaskItem.ID) -> Binding<Bool> {
        Binding(
            get: { detailTaskID == id },
            set: { isShown in
                guard !isShown, detailTaskID == id else { return }
                detailTaskID = nil
                if kindSwitchID == id {
                    // Switching kinds replaced the view the popover pointed at, such as a task chip
                    // becoming an event block in the Week view. Open it again on the new one.
                    openDetails(id)
                }
            }
        )
    }

    private func willSwitchKind(_ id: TaskItem.ID) {
        kindSwitchID = id
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            if kindSwitchID == id {
                kindSwitchID = nil
            }
        }
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
        insert(TaskItem(title: "New Task", due: due))
    }

    /// New Event from the toolbar: the next whole hour, on the calendar's day or today.
    private func addEvent() {
        switch destination {
        case .calendar:
            insertEvent(start: TaskItem.defaultEventStart(on: calendarDate))
        case .filter(.upcoming):
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
            insertEvent(start: TaskItem.defaultEventStart(on: tomorrow))
        case .filter(.today), .filter(.all):
            insertEvent(start: TaskItem.defaultEventStart(on: .now))
        default:
            destination = .filter(.all)
            insertEvent(start: TaskItem.defaultEventStart(on: .now))
        }
    }

    /// Without an end, the event lasts an hour.
    private func insertEvent(start: Date, end: Date? = nil) {
        insert(TaskItem(title: "New Event", start: start, end: end))
    }

    private func insert(_ task: TaskItem) {
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

    /// Marks all as done if any are open; otherwise reopens them. Events have no done state.
    private func toggleDone(_ ids: Set<TaskItem.ID>) {
        var tasks = document.file.tasks
        let toggled = tasks.indices.filter { ids.contains(tasks[$0].id) && !tasks[$0].isEvent }
        guard !toggled.isEmpty else { return }
        let markDone = toggled.contains { !tasks[$0].done }
        for index in toggled {
            tasks[index].done = markDone
        }
        document.file.tasks = tasks
    }

    /// Moves tasks to a day, or clears their due date when `day` is nil.
    /// Events keep their times, and can't lose their date. Repeating events move as a series,
    /// by as many days as the dragged `anchor` occurrence.
    private func reschedule(_ ids: Set<TaskItem.ID>, anchor: TaskItem?, to day: Date?) {
        let calendar = Calendar.current
        var tasks = document.file.tasks
        let days = day.flatMap { day in
            anchor?.due.flatMap { calendar.dateComponents([.day], from: $0, to: calendar.startOfDay(for: day)).day }
        }
        for index in tasks.indices where ids.contains(tasks[index].id) {
            if tasks[index].isRepeatingEvent {
                if let days {
                    tasks[index].moveSeries(byDays: days)
                }
            } else if let day {
                tasks[index].move(toDay: day)
            } else if !tasks[index].isEvent {
                tasks[index].due = nil
            }
        }
        guard tasks != document.file.tasks else { return }
        document.file.tasks = tasks
    }

    /// A drop on the week grid: the anchor event starts at `start`, other selected events shift
    /// by the same amount, and tasks move to that day.
    private func move(_ ids: Set<TaskItem.ID>, anchor: TaskItem, to start: Date) {
        var tasks = document.file.tasks
        // From the dragged occurrence, so a repeating series moves by as much as that one did.
        let offset = anchor.start.map { start.timeIntervalSince($0) }
        for index in tasks.indices where ids.contains(tasks[index].id) {
            if tasks[index].isRepeatingEvent, let eventStart = tasks[index].start, let offset {
                tasks[index].moveSeries(toStart: eventStart.addingTimeInterval(offset))
            } else if let eventStart = tasks[index].start, let offset {
                tasks[index].move(toStart: eventStart.addingTimeInterval(offset))
            } else {
                // Dragged along with a task: events keep their time of day, tasks just change day.
                tasks[index].move(toDay: start)
            }
        }
        guard tasks != document.file.tasks else { return }
        document.file.tasks = tasks
    }
}
