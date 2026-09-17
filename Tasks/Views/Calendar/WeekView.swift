import AppKit
import SwiftUI

/// Calendar.app-style week: tasks in an all-day strip, events as blocks on an hourly grid.
struct WeekView: View {
    let visibleDate: Date
    @Binding var tasks: [TaskItem]
    let tasksByDay: [Date: [TaskItem]]
    let selection: Set<TaskItem.ID>
    let actions: CalendarActions

    static let hourHeight: CGFloat = 48
    static let gutterWidth: CGFloat = 52
    private static let maxAllDayRows = 3

    /// The hour grid's scroll view, for placing the drag preview over it.
    @State private var viewport: CGRect = .zero

    var body: some View {
        let days = CalendarGrid.weekDays(containing: visibleDate)

        VStack(spacing: 0) {
            columns(days, gutter: Color.clear) { day in
                HStack(spacing: 4) {
                    Text(day, format: .dateTime.weekday(.abbreviated))
                        .foregroundStyle(.secondary)
                    DayNumber(day: day)
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            allDayStrip(days)
            Divider()
            timeGrid(days)
        }
    }

    // MARK: - Pieces

    /// The hour gutter's width, then one column per day with separators between them.
    private func columns<Gutter: View, Column: View>(
        _ days: [Date],
        gutter: Gutter,
        @ViewBuilder column: @escaping (Date) -> Column
    ) -> some View {
        HStack(spacing: 0) {
            gutter.frame(width: Self.gutterWidth)
            ForEach(days, id: \.self) { day in
                Rectangle().fill(.separator).frame(width: 1)
                column(day)
            }
        }
    }

    private func allDayStrip(_ days: [Date]) -> some View {
        let dayTasks = days.map { day in (tasksByDay[day] ?? []).filter { !$0.isEvent } }
        let rows = min(max(dayTasks.map(\.count).max() ?? 0, 1), Self.maxAllDayRows)
        let height = CGFloat(rows) * (TaskChip.height + 2) + 8

        return columns(days, gutter: allDayLabel) { day in
            let index = days.firstIndex(of: day) ?? 0
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(dayTasks[index]) { task in
                        TaskChip(task: $tasks[id: task.id], occurrence: task, isSelected: selection.contains(task.id), actions: actions)
                    }
                }
                .padding(4)
            }
            .frame(maxWidth: .infinity)
            .calendarDropTarget(day: day, actions: actions)
        }
        .frame(height: height)
    }

    private var allDayLabel: some View {
        Text("all-day")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, 6)
            .padding(.top, 6)
    }

    private func timeGrid(_ days: [Date]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                columns(days, gutter: HourGutter()) { day in
                    DayTimeline(
                        day: day,
                        tasks: $tasks,
                        events: (tasksByDay[day] ?? []).filter(\.isEvent),
                        selection: selection,
                        actions: actions
                    )
                }
                .frame(height: Self.hourHeight * 24)
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(CalendarDragState.space)) } action: {
                viewport = $0
            }
            .overlay(alignment: .topLeading) {
                TimeGridDropPreview(viewport: viewport)
            }
            .clipped()
            .onAppear {
                // Start just above the current hour this week, or at the start of a working day.
                let calendar = Calendar.current
                let hour = days.contains(where: calendar.isDateInToday)
                    ? max(calendar.component(.hour, from: .now) - 1, 0)
                    : 8
                proxy.scrollTo(hour, anchor: .top)
            }
        }
    }
}

/// Hour labels beside the grid, plus the current time in red.
private struct HourGutter: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            let calendar = Calendar.current
            let time = calendar.dateComponents([.hour, .minute], from: context.date)
            let nowMinute = (time.hour ?? 0) * 60 + (time.minute ?? 0)

            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { hour in
                        // Hidden at midnight and when the current time label would cover it.
                        let isHidden = hour == 0 || abs(hour * 60 - nowMinute) < 12
                        Text(EventLayout.date(on: context.date, minute: hour * 60), format: .dateTime.hour())
                            .opacity(isHidden ? 0 : 1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .offset(y: -7)
                            .frame(height: WeekView.hourHeight, alignment: .top)
                            .id(hour)
                    }
                }
                Text(context.date, format: .dateTime.hour().minute())
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                    .offset(y: CGFloat(nowMinute) / 60 * WeekView.hourHeight - 7)
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.trailing, 6)
        }
    }
}

/// One day of the hourly grid: hour lines, event blocks side by side when they overlap,
/// and the red now-line on today.
private struct DayTimeline: View {
    let day: Date
    @Binding var tasks: [TaskItem]
    let events: [TaskItem]
    let selection: Set<TaskItem.ID>
    let actions: CalendarActions

    @Environment(CalendarDragState.self) private var drag
    /// The minutes covered while dragging across empty grid to create an event.
    @State private var draft: (start: Int, end: Int)?

    private var hourHeight: CGFloat { WeekView.hourHeight }

    var body: some View {
        let placements = EventLayout.placements(for: events, on: day)

        ZStack(alignment: .topLeading) {
            ForEach(1..<24, id: \.self) { hour in
                Rectangle()
                    .fill(.separator)
                    .frame(height: 1)
                    .padding(.top, CGFloat(hour) * hourHeight)
            }

            GeometryReader { geometry in
                let width = max(geometry.size.width - 6, 0)
                ForEach(placements, id: \.id) { placement in
                    let columnWidth = width / CGFloat(placement.columnCount)
                    let height = CGFloat(placement.endMinute - placement.startMinute) / 60 * hourHeight
                    EventBlock(
                        task: $tasks[id: placement.id],
                        occurrence: events.first { $0.id == placement.id },
                        height: height - 2,
                        isSelected: selection.contains(placement.id),
                        actions: actions
                    )
                    .frame(width: max(columnWidth - 2, 0), height: max(height - 2, 0))
                    // Padding rather than offset, so the details popover points at the block itself.
                    .padding(.leading, CGFloat(placement.column) * columnWidth + 1)
                    .padding(.top, CGFloat(placement.startMinute) / 60 * hourHeight + 1)
                }
            }

            if let draft {
                DraftBlock(day: day, range: draft)
                    .frame(height: CGFloat(draft.end - draft.start) / 60 * hourHeight - 2)
                    .padding(.top, CGFloat(draft.start) / 60 * hourHeight + 1)
                    .padding(.horizontal, 1)
                    .padding(.trailing, 5)
            }

            if Calendar.current.isDateInToday(day) {
                NowLine(hourHeight: hourHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isTaskTargeted ? Color.accentColor.opacity(0.08) : .clear)
        .animation(.easeOut(duration: 0.12), value: isTaskTargeted)
        .contentShape(.rect)
        // Drag across empty hours to create an event there. A drag that starts on an event
        // moves that event instead, since the block's own drag wins.
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .local)
                .onChanged { value in
                    draft = EventLayout.draggedRange(
                        fromY: value.startLocation.y, toY: value.location.y, hourHeight: hourHeight
                    )
                }
                .onEnded { _ in
                    guard let range = draft else { return }
                    draft = nil
                    actions.addEvent(
                        EventLayout.date(on: day, minute: range.start),
                        EventLayout.date(on: day, minute: range.end)
                    )
                }
        )
        .onTapGesture(count: 2, coordinateSpace: .local) { location in
            let start = date(atY: location.y)
            actions.addEvent(start, start.addingTimeInterval(TaskItem.defaultEventDuration))
        }
        .onTapGesture { actions.clearSelection() }
        .calendarDropZone(.timeline(day))
    }

    /// A task dragged over the grid moves to this day; events show a block at their new time instead.
    private var isTaskTargeted: Bool {
        drag.target == .day(day) && drag.session?.task.isEvent == false
    }

    private func date(atY y: CGFloat) -> Date {
        EventLayout.date(on: day, minute: EventLayout.snappedMinute(atY: y, hourHeight: hourHeight))
    }
}

/// The outline of the event being drawn by dragging, with its live time range.
private struct DraftBlock: View {
    let day: Date
    let range: (start: Int, end: Int)

    var body: some View {
        let start = EventLayout.date(on: day, minute: range.start)
        let end = EventLayout.date(on: day, minute: range.end)
        let time: Date.FormatStyle = .dateTime.hour().minute()
        let isShort = range.end - range.start < 30

        HStack(spacing: 0) {
            Rectangle().fill(.tint).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                if !isShort {
                    Text("New Event").font(.callout.weight(.semibold))
                }
                Text("\(start.formatted(time))–\(end.formatted(time))")
                    .font(.caption)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, isShort ? 0 : 3)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.accentColor.opacity(0.3))
        .clipShape(.rect(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

private struct NowLine: View {
    let hourHeight: CGFloat

    var body: some View {
        TimelineView(.everyMinute) { context in
            let time = Calendar.current.dateComponents([.hour, .minute], from: context.date)
            let y = CGFloat((time.hour ?? 0) * 60 + (time.minute ?? 0)) / 60 * hourHeight

            HStack(spacing: 0) {
                Circle().fill(.red).frame(width: 7, height: 7)
                Rectangle().fill(.red).frame(height: 1.5)
            }
            .padding(.top, y - 3.5)
            .offset(x: -3.5)
        }
        .allowsHitTesting(false)
    }
}

/// An event on the hourly grid: a tinted block with a colored edge, its title and time.
private struct EventBlock: View {
    @Binding var task: TaskItem
    /// The occurrence this block stands for, when the event repeats.
    let occurrence: TaskItem?
    let height: CGFloat
    let isSelected: Bool
    let actions: CalendarActions

    var body: some View {
        let title = task.title.isEmpty ? "Untitled" : task.title
        let shown = occurrence ?? task

        HStack(spacing: 0) {
            Rectangle()
                .fill(isSelected ? Color.white.opacity(0.7) : .accentColor)
                .frame(width: 3)
            Group {
                if height < 30 {
                    // Too short for two lines: title and start time side by side.
                    HStack(spacing: 4) {
                        Text(title).fontWeight(.semibold)
                        if let time = shown.startTimeLabel {
                            Text(time).monospacedDigit().opacity(0.75)
                        }
                    }
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.vertical, height < 16 ? 0 : 2)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(max(Int((height - 20) / 16), 1))
                        if let range = shown.timeRangeLabel {
                            HStack(spacing: 3) {
                                Text(range).monospacedDigit()
                                if task.recurrence != nil {
                                    Image(systemName: "repeat")
                                }
                            }
                            .font(.caption)
                            .opacity(0.75)
                            .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .padding(.horizontal, 5)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(isSelected ? Color.white : .primary)
        .background(isSelected ? Color.accentColor : Color.accentColor.opacity(0.18))
        // Opaque underneath, so hour lines don't show through the tint.
        .background(.background)
        .clipShape(.rect(cornerRadius: 5))
        .opacity(shown.hasEnded() && !isSelected ? 0.55 : 1)
        .contentShape(.rect)
        .onTapGesture {
            actions.select(task.id, NSEvent.modifierFlags.contains(.command))
        }
        .calendarDragSource(task: shown, actions: actions)
        .contextMenu {
            Button("Delete", role: .destructive) {
                actions.delete([task.id])
            }
        }
        .popover(isPresented: actions.detailsShown(task.id), arrowEdge: .trailing) {
            TaskDetailView(task: $task)
        }
        .help([title, shown.timeRangeLabel, task.recurrence?.summary].compactMap { $0 }.joined(separator: "\n"))
    }
}
