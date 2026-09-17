import SwiftUI

/// The drag in progress in the calendar and the frames of the places it can land.
///
/// Dragging is done with SwiftUI gestures instead of system drag and drop, so the calendar can
/// show where an item will land while it moves: a block that slides between time slots, or a
/// chip that follows the pointer over highlighted days.
@MainActor @Observable
final class CalendarDragState {
    /// The coordinate space every frame and pointer location is measured in.
    static let space = "calendarDrag"

    struct Session {
        let task: TaskItem
        /// Everything that moves: the dragged item, plus the selection when it's part of it.
        let ids: Set<TaskItem.ID>
        /// Where the pointer grabbed the item, from its top-left corner.
        let grab: CGSize
        let size: CGSize
    }

    private(set) var session: Session?
    private(set) var location: CGPoint = .zero
    private(set) var target: CalendarDropTarget?
    /// Reported by drop zones as they lay out. Not observed: views only need them mid-drag,
    /// and they change on every scroll.
    @ObservationIgnored var zones: [CalendarDropZone: CGRect] = [:]

    func isMoving(_ id: TaskItem.ID) -> Bool {
        session?.ids.contains(id) ?? false
    }

    func update(task: TaskItem, ids: Set<TaskItem.ID>, frame: CGRect, start: CGPoint, location: CGPoint) {
        if session == nil {
            session = Session(
                task: task, ids: ids,
                grab: CGSize(width: start.x - frame.minX, height: start.y - frame.minY),
                size: frame.size
            )
        }
        self.location = location
        let newTarget = CalendarDrop.target(
            at: location, zones: zones, isEvent: task.isEvent,
            grabOffsetY: session?.grab.height ?? 0, hourHeight: WeekView.hourHeight
        )
        if newTarget != target {
            target = newTarget
        }
    }

    /// Ends the drag and returns what was dragged and where it landed.
    func finish() -> (session: Session, target: CalendarDropTarget?)? {
        defer {
            session = nil
            target = nil
        }
        return session.map { ($0, target) }
    }
}

// MARK: - Sources and zones

private struct CalendarDragSource: ViewModifier {
    let task: TaskItem
    let actions: CalendarActions
    @Environment(CalendarDragState.self) private var drag
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(CalendarDragState.space)) } action: {
                frame = $0
            }
            .opacity(drag.isMoving(task.id) ? 0.35 : 1)
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named(CalendarDragState.space))
                    .onChanged { value in
                        drag.update(
                            task: task, ids: actions.dragGroup(task.id), frame: frame,
                            start: value.startLocation, location: value.location
                        )
                    }
                    .onEnded { _ in
                        guard let result = drag.finish() else { return }
                        actions.dropDragged(result.session.ids, result.session.task, result.target)
                    }
            )
    }
}

private struct CalendarDropZoneReporter: ViewModifier {
    let zone: CalendarDropZone
    @Environment(CalendarDragState.self) private var drag
    @State private var frame: CGRect?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(CalendarDragState.space)) } action: { newFrame in
                frame = newFrame
                drag.zones[zone] = newFrame
            }
            .onDisappear {
                // The next month's grid can show the same day and register it before this one leaves.
                if drag.zones[zone] == frame {
                    drag.zones[zone] = nil
                }
            }
    }
}

extension View {
    /// Lets the item be dragged to another day, time or the undated tray.
    func calendarDragSource(task: TaskItem, actions: CalendarActions) -> some View {
        modifier(CalendarDragSource(task: task, actions: actions))
    }

    func calendarDropZone(_ zone: CalendarDropZone) -> some View {
        modifier(CalendarDropZoneReporter(zone: zone))
    }
}

// MARK: - Feedback

/// The chip that follows the pointer while dragging over days or the tray.
/// Over the hour grid, the grid shows a snapped block instead.
struct CalendarDragPreview: View {
    @Environment(CalendarDragState.self) private var drag

    var body: some View {
        if let session = drag.session, !isOverTimeGrid {
            let width = min(max(session.size.width, 120), 200)
            // Keep the chip close to the pointer even when a tall event block was grabbed low down.
            let grabX = min(session.grab.width, width - 12)
            let grabY = min(session.grab.height, TaskChip.height / 2)

            TaskChip(task: .constant(session.task), isSelected: true, actions: .inert, isDraggable: false)
                .frame(width: width)
                .overlay(alignment: .topTrailing) {
                    if session.ids.count > 1 {
                        Text("\(session.ids.count)")
                            .font(.caption2.bold())
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .background(.red, in: .capsule)
                            .offset(x: 6, y: -6)
                    }
                }
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .opacity(drag.target == nil ? 0.6 : 1)
                .offset(x: drag.location.x - grabX, y: drag.location.y - grabY)
                .allowsHitTesting(false)
        }
    }

    private var isOverTimeGrid: Bool {
        if case .time = drag.target { true } else { false }
    }
}

/// Where a dragged event will land on the hour grid: a block at the snapped time that slides
/// from slot to slot and across days. Placed over the grid's scroll view and clipped to it.
struct TimeGridDropPreview: View {
    /// The scroll view's frame in the drag coordinate space.
    let viewport: CGRect
    @Environment(CalendarDragState.self) private var drag

    var body: some View {
        if let session = drag.session, case .time(let day, let minute) = drag.target,
           let column = drag.zones[.timeline(day)] {
            let hourHeight = WeekView.hourHeight
            let duration = session.task.end.flatMap { end in session.task.start.map { end.timeIntervalSince($0) } }
                ?? TaskItem.defaultEventDuration
            let minutes = min(max(Int(duration / 60), EventLayout.minimumMinutes), EventLayout.minutesPerDay - minute)
            let start = EventLayout.date(on: day, minute: minute)

            MovingEventBlock(title: session.task.title, start: start, end: start.addingTimeInterval(duration))
                .frame(width: max(column.width - 8, 0), height: max(CGFloat(minutes) / 60 * hourHeight - 2, 0))
                .offset(
                    x: column.minX - viewport.minX + 1,
                    y: column.minY - viewport.minY + CGFloat(minute) / 60 * hourHeight + 1
                )
                .animation(.snappy(duration: 0.16), value: drag.target)
                .allowsHitTesting(false)
        }
    }
}

private struct MovingEventBlock: View {
    let title: String
    let start: Date
    let end: Date

    var body: some View {
        let time: Date.FormatStyle = .dateTime.hour().minute()

        HStack(spacing: 0) {
            Rectangle().fill(.white.opacity(0.7)).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title.isEmpty ? "Untitled" : title)
                    .font(.callout.weight(.semibold))
                Text("\(start.formatted(time))–\(end.formatted(time))")
                    .font(.caption)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
        .background(Color.accentColor.opacity(0.9), in: .rect(cornerRadius: 5))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}
