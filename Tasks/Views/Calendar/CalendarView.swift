import SwiftUI

/// Everything a calendar subview can do to tasks, so the views stay free of document logic.
struct CalendarActions {
    var select: (TaskItem.ID, _ extend: Bool) -> Void
    var clearSelection: () -> Void
    var add: (Date?) -> Void
    /// Adds an event from a start to an end time.
    var addEvent: (Date, Date) -> Void
    /// What moves when an item is dragged: the item, or the whole selection when it's part of it.
    var dragGroup: (TaskItem.ID) -> Set<TaskItem.ID>
    /// Moves dragged items (with the one under the pointer as anchor) to where they were dropped.
    /// The anchor is the occurrence that was dragged, for repeating events.
    var dropDragged: (Set<TaskItem.ID>, _ anchor: TaskItem, CalendarDropTarget?) -> Void
    var toggleDone: (Set<TaskItem.ID>) -> Void
    var delete: (Set<TaskItem.ID>) -> Void
    /// Whether a task's details popover is open; setting false closes it.
    var detailsShown: (TaskItem.ID) -> Binding<Bool>

    /// Does nothing, for chips drawn only as a picture, such as the one following a drag.
    @MainActor static let inert = CalendarActions(
        select: { _, _ in }, clearSelection: {}, add: { _ in }, addEvent: { _, _ in },
        dragGroup: { [$0] }, dropDragged: { _, _, _ in }, toggleDone: { _ in }, delete: { _ in },
        detailsShown: { _ in .constant(false) }
    )
}

struct CalendarView: View {
    @Binding var tasks: [TaskItem]
    @Binding var selection: Set<TaskItem.ID>
    @Binding var visibleDate: Date
    @Binding var mode: CalendarMode
    @Binding var detailTaskID: TaskItem.ID?
    let onAdd: (Date?) -> Void
    let onAddEvent: (Date, Date) -> Void
    /// Moves tasks to a day, or clears their due date when it's nil. The anchor is the dragged
    /// occurrence, so repeating events move by as many days as it did. With `clearsTime`,
    /// tasks lose their due time.
    let onReschedule: (Set<TaskItem.ID>, _ anchor: TaskItem?, Date?, _ clearsTime: Bool) -> Void
    /// Moves items to a time: the anchor starts or is due then, other timed items shift by as much,
    /// and untimed tasks become due then.
    let onMove: (Set<TaskItem.ID>, _ anchor: TaskItem, Date) -> Void
    let onToggleDone: (Set<TaskItem.ID>) -> Void
    let onDelete: (Set<TaskItem.ID>) -> Void
    /// Whether a task's details popover is open; setting false closes it.
    let detailsShown: (TaskItem.ID) -> Binding<Bool>

    @SceneStorage("calendarTrayShown") private var isTrayShown = false
    @State private var drag = CalendarDragState()
    @FocusState private var isFocused: Bool

    var body: some View {
        let visible = TaskFilter.all.apply(to: tasks)
        let shownDays = mode == .month
            ? CalendarGrid.monthDays(containing: visibleDate)
            : CalendarGrid.weekDays(containing: visibleDate)
        let byDay = CalendarGrid.tasksByDay(visible, in: CalendarGrid.interval(of: shownDays))

        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                switch mode {
                case .month:
                    MonthGridView(
                        visibleDate: visibleDate, tasks: $tasks, tasksByDay: byDay,
                        selection: selection, actions: actions
                    )
                case .week:
                    WeekView(
                        visibleDate: visibleDate, tasks: $tasks, tasksByDay: byDay,
                        selection: selection, actions: actions
                    )
                }
                if isTrayShown {
                    Rectangle().fill(.separator).frame(width: 1)
                    UndatedTray(
                        tasks: $tasks,
                        undated: visible.filter { $0.due == nil && !$0.done },
                        selection: selection, actions: actions
                    )
                }
            }
        }
        .coordinateSpace(.named(CalendarDragState.space))
        .overlay(alignment: .topLeading) {
            CalendarDragPreview()
        }
        .environment(drag)
        .background(.background)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .background { modeShortcuts }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $mode) {
                    ForEach(CalendarMode.allCases) { Text($0.title) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            ToolbarItem {
                Button("Undated Tasks", systemImage: isTrayShown ? "tray.fill" : "tray") {
                    isTrayShown.toggle()
                }
                .help("Show tasks without a due date")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(Text(visibleDate, format: .dateTime.month(.wide)).bold()) \(Text(visibleDate, format: .dateTime.year()))")
                .font(.title)
            Spacer()
            HStack(spacing: 4) {
                Button("Previous", systemImage: "chevron.left") { step(-1) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Today") { visibleDate = .now }
                    .keyboardShortcut("t", modifiers: .command)
                Button("Next", systemImage: "chevron.right") { step(1) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Invisible buttons that give ⌘1 and ⌘2 to the Month/Week picker.
    private var modeShortcuts: some View {
        HStack {
            Button("Month") { mode = .month }.keyboardShortcut("1", modifiers: .command)
            Button("Week") { mode = .week }.keyboardShortcut("2", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func step(_ value: Int) {
        visibleDate = CalendarGrid.step(visibleDate, mode: mode, by: value)
    }

    /// Dragging one chip of a multi-selection moves the whole selection.
    private func withSelection(_ dragged: Set<TaskItem.ID>) -> Set<TaskItem.ID> {
        dragged.isDisjoint(with: selection) ? dragged : dragged.union(selection)
    }

    private var actions: CalendarActions {
        CalendarActions(
            select: { id, extend in
                if extend {
                    selection.formSymmetricDifference([id])
                } else {
                    selection = [id]
                    detailTaskID = id
                }
                isFocused = true
            },
            clearSelection: {
                selection = []
                isFocused = true
            },
            add: onAdd,
            addEvent: onAddEvent,
            dragGroup: { withSelection([$0]) },
            dropDragged: { ids, anchor, target in
                guard let target else { return }
                // Items slide into their new place rather than jumping there.
                withAnimation(.snappy(duration: 0.25)) {
                    switch target {
                    case .day(let day):
                        onReschedule(ids, anchor, day, false)
                    case .allDay(let day):
                        onReschedule(ids, anchor, day, true)
                    case .time(let day, let minute):
                        onMove(ids, anchor, EventLayout.date(on: day, minute: minute))
                    case .undated:
                        onReschedule(ids, anchor, nil, false)
                    }
                }
            },
            toggleDone: onToggleDone,
            delete: onDelete,
            detailsShown: detailsShown
        )
    }
}

// MARK: - Shared pieces

/// Day number in the Calendar.app style: a red capsule for today, the month name on the 1st.
struct DayNumber: View {
    let day: Date
    var dimmed = false

    var body: some View {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(day)
        let format: Date.FormatStyle = calendar.component(.day, from: day) == 1
            ? .dateTime.month(.abbreviated).day()
            : .dateTime.day()

        Text(day, format: format)
            .monospacedDigit()
            .fontWeight(isToday ? .semibold : .regular)
            .foregroundStyle(isToday ? Color.white : dimmed ? Color.secondary : Color.primary)
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 22)
            .background {
                if isToday {
                    Capsule().fill(.red)
                }
            }
    }
}

private struct CalendarDayTarget: ViewModifier {
    let day: Date?
    let actions: CalendarActions
    let allDay: Bool
    @Environment(CalendarDragState.self) private var drag

    func body(content: Content) -> some View {
        let isTargeted = switch drag.target {
        case .day(let target), .allDay(let target): target == day
        case .undated: day == nil
        default: false
        }

        content
            .background(isTargeted ? Color.accentColor.opacity(0.12) : .clear)
            .animation(.easeOut(duration: 0.12), value: isTargeted)
            .contentShape(.rect)
            .onTapGesture(count: 2) { actions.add(day) }
            .onTapGesture { actions.clearSelection() }
            .calendarDropZone(day.map { allDay ? .allDay($0) : .day($0) } ?? .undated)
    }
}

extension View {
    /// Accepts dropped tasks, adds a task on double-click and clears the selection on click.
    /// A `nil` day means "no due date". The Week view's `allDay` row also clears a task's time.
    func calendarDropTarget(day: Date?, actions: CalendarActions, allDay: Bool = false) -> some View {
        modifier(CalendarDayTarget(day: day, actions: actions, allDay: allDay))
    }
}
