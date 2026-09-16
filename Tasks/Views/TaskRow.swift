import SwiftUI

struct TaskRow: View {
    @Binding var task: TaskItem

    var body: some View {
        let isFinished = task.isFinished()

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

            if let scheduleLabel = task.scheduleLabel {
                Text(scheduleLabel)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(task.isOverdue() ? .red : .secondary)
            }
        }
        .padding(.vertical, 2)
        .opacity(task.isEvent && isFinished ? 0.6 : 1)
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
