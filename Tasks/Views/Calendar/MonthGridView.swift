import SwiftUI

struct MonthGridView: View {
    let visibleDate: Date
    @Binding var tasks: [TaskItem]
    let tasksByDay: [Date: [TaskItem]]
    let selection: Set<TaskItem.ID>
    let actions: CalendarActions

    var body: some View {
        let calendar = Calendar.current
        let days = CalendarGrid.monthDays(containing: visibleDate)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(CalendarGrid.weekdaySymbols(), id: \.self) { symbol in
                    Text(symbol)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
            }
            Divider()

            if days.count == 42 {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(0..<6, id: \.self) { week in
                        GridRow {
                            ForEach(0..<7, id: \.self) { column in
                                let day = days[week * 7 + column]
                                DayCell(
                                    day: day,
                                    isInVisibleMonth: calendar.isDate(day, equalTo: visibleDate, toGranularity: .month),
                                    tasks: $tasks,
                                    dayTasks: tasksByDay[day] ?? [],
                                    selection: selection,
                                    actions: actions
                                )
                                .overlay(alignment: .trailing) {
                                    if column < 6 {
                                        Rectangle().fill(.separator).frame(width: 1)
                                    }
                                }
                            }
                        }
                        if week < 5 {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct DayCell: View {
    let day: Date
    let isInVisibleMonth: Bool
    @Binding var tasks: [TaskItem]
    let dayTasks: [TaskItem]
    let selection: Set<TaskItem.ID>
    let actions: CalendarActions

    @State private var height: CGFloat = 0
    @State private var isShowingAll = false

    private static let chipSpacing: CGFloat = 2
    private static let headerHeight: CGFloat = 26

    var body: some View {
        let shown = visibleTasks
        let hiddenCount = dayTasks.count - shown.count

        VStack(alignment: .leading, spacing: Self.chipSpacing) {
            HStack {
                Spacer()
                DayNumber(day: day, dimmed: !isInVisibleMonth)
                    .font(.callout)
            }
            ForEach(shown) { task in
                chip(task)
            }
            if hiddenCount > 0 {
                Button("\(hiddenCount) more") { isShowingAll = true }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .popover(isPresented: $isShowingAll, arrowEdge: .trailing) {
                        allTasksPopover
                    }
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(isInVisibleMonth ? Color.clear : Color.secondary.opacity(0.05))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .calendarDropTarget(day: day, actions: actions)
    }

    /// As many chips as fit; the last slot becomes "N more" when some don't.
    private var visibleTasks: ArraySlice<TaskItem> {
        let row = TaskChip.height + Self.chipSpacing
        let capacity = max(0, Int((height - Self.headerHeight - 8) / row))
        if dayTasks.count <= capacity {
            return dayTasks[...]
        }
        return dayTasks.prefix(max(0, capacity - 1))
    }

    private var allTasksPopover: some View {
        VStack(alignment: .leading, spacing: Self.chipSpacing) {
            Text(day, format: .dateTime.weekday(.wide).month().day())
                .font(.headline)
                .padding(.bottom, 4)
            ForEach(dayTasks) { task in
                chip(task, inMorePopover: true)
            }
        }
        .padding(10)
        .frame(width: 240)
    }

    private func chip(_ task: TaskItem, inMorePopover: Bool = false) -> some View {
        var chipActions = actions
        if isShowingAll, !inMorePopover {
            // The "more" popover shows this task too; only that copy presents its details.
            chipActions.detailsShown = { _ in .constant(false) }
        }
        // Chips in the "more" popover live in another window, outside the calendar's drag space.
        return TaskChip(
            task: $tasks[id: task.id], occurrence: task, isSelected: selection.contains(task.id), actions: chipActions,
            day: day, isDraggable: !inMorePopover
        )
    }
}
