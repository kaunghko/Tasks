import AppKit
import SwiftUI

struct ContentView: View {
    @Binding var document: TaskDocument
    /// Where the document is saved, which keeps its notifications apart from other documents'.
    var fileURL: URL?

    @State private var destination: AppDestination? = .filter(.all)
    @State private var selection: Set<TaskItem.ID> = []
    /// The task being edited: expanded in place in a list, or in a popover on the calendar.
    @State private var detailTaskID: TaskItem.ID?
    /// Where the caret goes in a list row as it expands.
    @State private var caretTarget: CaretTarget = .selectedTitle
    /// The list's order when a row expanded. Kept while it's open, so an edit that re-sorts
    /// the list, like setting a due date, doesn't move the row away from the cursor.
    @State private var frozenOrder: [TaskItem.ID]?
    /// Set briefly while an item switches between task and event from its popover.
    @State private var kindSwitchID: TaskItem.ID?
    /// A task or event as it was created. Closed without a change, it's removed as a mistaken click.
    @State private var untouchedNew: TaskItem?
    @State private var isPaletteShown = false
    /// The sidebar starts hidden so the task list opens uncluttered.
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var calendarDate = Date.now
    @SceneStorage("calendarMode") private var calendarMode: CalendarMode = .month
    /// A task the list should scroll to and then open details for.
    @State private var revealID: TaskItem.ID?
    /// Where the caret goes once the revealed task's row expands.
    @State private var revealCaret: CaretTarget = .selectedTitle
    /// Stands in for `fileURL` until an untitled document is saved.
    @State private var untitledKey = UUID().uuidString
    /// The key the notifications were last scheduled under, so a rename or first save drops the old ones.
    @State private var scheduledKey: String?

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
                            .keyboardShortcut("n", modifiers: .command)
                            .help("New task (⌘N)")
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
        .onChange(of: destination) {
            // An expanded row shouldn't reopen as a popover in the calendar, or vice versa.
            detailTaskID = nil
            frozenOrder = nil
        }
        .onChange(of: detailTaskID) { old, new in
            guard let created = untouchedNew, created.id == old, new != old else { return }
            untouchedNew = nil
            if document.file.tasks.first(where: { $0.id == created.id }) == created {
                delete([created.id])
            }
        }
        .environment(\.willSwitchKind, willSwitchKind)
        .task(id: NotificationInput(tasks: document.file.tasks, key: notificationKey)) {
            await scheduleNotifications()
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
        // Keep the expanded task, so an edit that moves it out of this list
        // (marking it done in Today, switching it to an event) doesn't close it under the cursor.
        if let id = detailTaskID, !tasks.contains(where: { $0.id == id }),
           let open = document.file.tasks.first(where: { $0.id == id }) {
            tasks.append(open.currentOccurrence())
            tasks.sort(by: TaskFilter.displayOrder)
        }
        if let frozenOrder {
            // Tasks added meanwhile keep their sorted place after the ones on screen.
            let positions = Dictionary(frozenOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            tasks = tasks.enumerated()
                .sorted { (positions[$0.element.id] ?? frozenOrder.count + $0.offset) < (positions[$1.element.id] ?? frozenOrder.count + $1.offset) }
                .map(\.element)
        }
        return ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(tasks) { task in
                    TaskRow(
                        task: $document.file.tasks[id: task.id],
                        occurrence: task,
                        isExpanded: detailTaskID == task.id,
                        caret: caretTarget,
                        onOpen: { expand(task.id, caret: $0) },
                        onClose: { byKeyboard in
                            let id = task.id
                            // A click outside may have opened another task already.
                            guard detailTaskID == id else { return }
                            expand(nil)
                            // Esc leaves the task selected, so Space and Delete act on it.
                            if byKeyboard { selection = [id] } else { selection.remove(id) }
                        }
                    )
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
                // Let the row settle on screen before it expands.
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                expand(id, caret: revealCaret)
                revealID = nil
            }
            .onChange(of: selection) { _, newValue in
                // Selecting another task, such as with ⌘1–⌘9, closes the expanded row. Clicks are left to
                // `TaskRow`: its tap gesture opens the clicked task, and a click elsewhere closes the row.
                let isClick = [.leftMouseDown, .leftMouseUp].contains(NSApp.currentEvent?.type)
                guard revealID == nil, !isClick, let id = detailTaskID, !newValue.isEmpty, !newValue.contains(id)
                else { return }
                expand(nil)
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

    private var notificationKey: String {
        fileURL?.path ?? untitledKey
    }

    /// Schedules notifications a moment after the tasks stop changing, then again every hour
    /// so repeating events keep getting scheduled while the document stays open.
    private func scheduleNotifications() async {
        try? await Task.sleep(for: .seconds(1))
        let key = notificationKey
        while !Task.isCancelled {
            if let old = scheduledKey, old != key {
                await NotificationScheduler.shared.update(documentKey: old, reminders: [])
            }
            scheduledKey = key
            await NotificationScheduler.shared.update(
                documentKey: key, reminders: Reminders.reminders(for: document.file.tasks))
            try? await Task.sleep(for: .seconds(3600))
        }
    }

    /// ⌘1–⌘9: selects the task at that position in the list and scrolls to it.
    private func selectTask(at index: Int, in tasks: [TaskItem], proxy: ScrollViewProxy) {
        guard tasks.indices.contains(index) else { return }
        selection = [tasks[index].id]
        proxy.scrollTo(tasks[index].id)
    }

    /// Expands a list row, or closes the expanded one when `id` is nil.
    private func expand(_ id: TaskItem.ID?, caret: CaretTarget = .selectedTitle) {
        if id != nil, frozenOrder == nil {
            frozenOrder = currentFilter.apply(to: document.file.tasks).map(\.id)
        }
        // Not animated here: the List would pass the animation to its table, which then fades the
        // whole row in as if reloading it, and the title and checkbox blink. `TaskRow` fades in its fields.
        caretTarget = caret
        detailTaskID = id

        guard id == nil, frozenOrder != nil else { return }
        // Re-sort once the row has closed. Doing both at once leaves the List with stale row heights.
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard detailTaskID == nil else { return }
            withAnimation(.easeOut(duration: 0.15)) { frozenOrder = nil }
        }
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

    /// Opens a task's popover or expands its row once the chip or row is on screen.
    private func openDetails(_ id: TaskItem.ID, caret: CaretTarget = .selectedTitle) {
        if destination == .calendar {
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                detailTaskID = id
            }
        } else {
            revealCaret = caret
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
            openDetails(task.id, caret: .title((task.title as NSString).length))
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
        untouchedNew = task
        selection = [task.id]
        openDetails(task.id)
    }

    private func delete(_ ids: Set<TaskItem.ID>) {
        guard !ids.isEmpty else { return }
        if let detailTaskID, ids.contains(detailTaskID) {
            expand(nil)
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
    private func reschedule(_ ids: Set<TaskItem.ID>, anchor: TaskItem?, to day: Date?, clearsTime: Bool) {
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
                if clearsTime {
                    tasks[index].dueTime = nil
                }
            } else if !tasks[index].isEvent {
                tasks[index].due = nil
            }
        }
        guard tasks != document.file.tasks else { return }
        document.file.tasks = tasks
    }

    /// A drop on the week grid: the anchor starts or is due at `start`, other timed items shift
    /// by the same amount, and untimed tasks become due at `start`.
    private func move(_ ids: Set<TaskItem.ID>, anchor: TaskItem, to start: Date) {
        var tasks = document.file.tasks
        // From the dragged occurrence, so a repeating series moves by as much as that one did.
        let offset = anchor.scheduledTime.map { start.timeIntervalSince($0) }
        for index in tasks.indices where ids.contains(tasks[index].id) {
            if tasks[index].isRepeatingEvent, let eventStart = tasks[index].start, let offset {
                tasks[index].moveSeries(toStart: eventStart.addingTimeInterval(offset))
            } else if let time = tasks[index].scheduledTime, let offset {
                tasks[index].move(toTime: time.addingTimeInterval(offset))
            } else if tasks[index].isEvent {
                // Dragged along with an untimed task: events keep their time of day.
                tasks[index].move(toDay: start)
            } else {
                tasks[index].move(toTime: start)
            }
        }
        guard tasks != document.file.tasks else { return }
        document.file.tasks = tasks
    }
}

/// What notifications depend on; a change reschedules them.
private struct NotificationInput: Equatable {
    var tasks: [TaskItem]
    var key: String
}
