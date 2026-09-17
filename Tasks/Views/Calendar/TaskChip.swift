import AppKit
import SwiftUI

/// A compact, draggable task used in calendar cells and the undated tray.
struct TaskChip: View {
    @Binding var task: TaskItem
    /// The occurrence this chip stands for, when a repeating event shows up on many days.
    var occurrence: TaskItem?
    let isSelected: Bool
    let actions: CalendarActions
    /// The calendar day this chip sits on. An event that started on an earlier day shows no start time there.
    var day: Date?
    var isDraggable = true

    static let height: CGFloat = 18

    var body: some View {
        let shown = occurrence ?? task

        HStack(spacing: 4) {
            if task.isEvent {
                EventBar(color: isSelected ? .white : .accentColor)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 2)
                if let time = shown.startTimeLabel, day.map({ Calendar.current.isDate($0, inSameDayAs: shown.start!) }) ?? true {
                    Text(time)
                        .monospacedDigit()
                        // The title truncates first; a cut-off time is useless.
                        .fixedSize()
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
                }
            } else {
                Toggle(isOn: $task.done) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .controlSize(.mini)
                if let time = task.dueTimeLabel {
                    Text(time)
                        .monospacedDigit()
                        .fixedSize()
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
                }
            }
            Text(task.title.isEmpty ? "Untitled" : task.title)
                .lineLimit(1)
                .strikethrough(task.done)
                .foregroundStyle(foreground)
            if let recurrence = task.recurrence {
                Image(systemName: "repeat")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
                    .help(recurrence.summary)
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, 4)
        .frame(height: Self.height)
        .background(background, in: .rect(cornerRadius: 4))
        .opacity(shown.isEvent && shown.hasEnded() && !isSelected ? 0.55 : 1)
        .contentShape(.rect)
        .onTapGesture {
            actions.select(task.id, NSEvent.modifierFlags.contains(.command))
        }
        .modifier(DragSourceIfEnabled(task: shown, actions: actions, isEnabled: isDraggable))
        .contextMenu {
            if !task.isEvent {
                Button(task.done ? "Mark as Not Done" : "Mark as Done") {
                    actions.toggleDone([task.id])
                }
                Divider()
            }
            Button("Delete", role: .destructive) {
                actions.delete([task.id])
            }
        }
        .popover(isPresented: actions.detailsShown(task.id), arrowEdge: .trailing) {
            TaskDetailView(task: $task)
        }
        .help(task.title)
    }

    private var foreground: Color {
        if isSelected { return .white }
        if task.done { return .secondary }
        return task.isOverdue() ? .red : .primary
    }

    private var background: Color {
        if isSelected { return .accentColor }
        if task.done { return .secondary.opacity(0.1) }
        // Events sit on a plain background with their bar; tasks get a tinted chip.
        if task.isEvent { return .clear }
        return task.isOverdue() ? .red.opacity(0.15) : .accentColor.opacity(0.15)
    }
}

private struct DragSourceIfEnabled: ViewModifier {
    let task: TaskItem
    let actions: CalendarActions
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.calendarDragSource(task: task, actions: actions)
        } else {
            content
        }
    }
}
