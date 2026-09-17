import AppKit
import SwiftUI

struct TaskRow: View {
    @Binding var task: TaskItem
    /// The occurrence to show the schedule of, when the event repeats.
    var occurrence: TaskItem?
    /// Called on a plain click anywhere but the checkbox.
    var onOpen: () -> Void = {}

    var body: some View {
        let shown = occurrence ?? task
        let isFinished = shown.isFinished()

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if task.isEvent {
                EventBar()
                    .frame(height: 14)
                    // Checkbox width, so event and task titles line up.
                    .frame(width: 16)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            } else {
                Toggle(isOn: $task.done) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }

            // Clicks here open the details. Not on the checkbox: checking a task off shouldn't
            // open its popover, least of all a repeating one that stays in the list.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title.isEmpty ? "Untitled" : task.title)
                        .strikethrough(task.done)
                        .foregroundStyle(isFinished ? .secondary : .primary)
                    if !task.notes.isEmpty {
                        Text(task.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let progress = task.subtaskProgress {
                    // Not a `Label`: the List aligns row separators to a Label's title,
                    // which cut the separator short under rows with subtasks.
                    HStack(spacing: 3) {
                        Image(systemName: "checklist")
                        Text("\(progress.done)/\(progress.total)")
                    }
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .help("\(progress.done) of \(progress.total) subtasks done")
                }

                if let recurrence = task.recurrence {
                    Image(systemName: "repeat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(recurrence.summary)
                }

                if let scheduleLabel = shown.scheduleLabel {
                    Text(scheduleLabel)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(shown.isOverdue() ? .red : .secondary)
                }
            }
            .contentShape(.rect)
            // Simultaneous, so the List still handles selection and ⌘/⇧-clicks.
            .simultaneousGesture(TapGesture().onEnded {
                if !NSEvent.modifierFlags.contains(.command), !NSEvent.modifierFlags.contains(.shift) {
                    onOpen()
                }
            })
        }
        .padding(.vertical, 2)
        .opacity(shown.isEvent && isFinished ? 0.6 : 1)
    }
}

/// The colored bar that stands in for a checkbox on events.
struct EventBar: View {
    var color: Color = .accentColor

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: 3)
    }
}
