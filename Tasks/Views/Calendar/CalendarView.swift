import SwiftUI

/// Everything a calendar subview can do to tasks, so the views stay free of document logic.
struct CalendarActions {
    var select: (TaskItem.ID, _ extend: Bool) -> Void
    var clearSelection: () -> Void
    var add: (Date?) -> Void
    /// Handles dropped task ids; `nil` clears the due date.
    var drop: ([String], Date?) -> Bool
    var toggleDone: (Set<TaskItem.ID>) -> Void
    var delete: (Set<TaskItem.ID>) -> Void
}

struct CalendarView: View {
    @Binding var tasks: [TaskItem]
    @Binding var selection: Set<TaskItem.ID>
    @Binding var visibleDate: Date
    @Binding var mode: CalendarMode
    let onAdd: (Date?) -> Void
    let onReschedule: (Set<TaskItem.ID>, Date?) -> Void
    let onToggleDone: (Set<TaskItem.ID>) -> Void
    let onDelete: (Set<TaskItem.ID>) -> Void

    @SceneStorage("calendarTrayShown") private var isTrayShown = false
    @FocusState private var isFocused: Bool

    var body: some View {
        let visible = TaskFilter.all.apply(to: tasks)
        let byDay = CalendarGrid.tasksByDay(visible)

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

    private var actions: CalendarActions {
        CalendarActions(
            select: { id, extend in
                if extend {
                    selection.formSymmetricDifference([id])
                } else {
                    selection = [id]
                }
                isFocused = true
            },
            clearSelection: {
                selection = []
                isFocused = true
            },
            add: onAdd,
            drop: { items, day in
                let dragged = Set(items.compactMap(UUID.init(uuidString:)))
                guard !dragged.isEmpty else { return false }
                // Dragging one chip of a multi-selection moves the whole selection.
                let ids = dragged.isDisjoint(with: selection) ? dragged : dragged.union(selection)
                onReschedule(ids, day)
                return true
            },
            toggleDone: onToggleDone,
            delete: onDelete
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

private struct CalendarDropTarget: ViewModifier {
    let day: Date?
    let actions: CalendarActions
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .background(isTargeted ? Color.accentColor.opacity(0.12) : .clear)
            .contentShape(.rect)
            .onTapGesture(count: 2) { actions.add(day) }
            .onTapGesture { actions.clearSelection() }
            .dropDestination(for: String.self) { items, _ in
                actions.drop(items, day)
            } isTargeted: {
                isTargeted = $0
            }
    }
}

extension View {
    /// Accepts dropped tasks, adds a task on double-click and clears the selection on click.
    /// A `nil` day means "no due date".
    func calendarDropTarget(day: Date?, actions: CalendarActions) -> some View {
        modifier(CalendarDropTarget(day: day, actions: actions))
    }
}
