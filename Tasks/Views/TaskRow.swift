import SwiftUI

struct TaskRow: View {
    @Binding var task: TaskItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle(isOn: $task.done) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title.isEmpty ? "Untitled" : task.title)
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? .secondary : .primary)
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

            if let dueLabel = task.dueLabel {
                Text(dueLabel)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(task.isOverdue() ? .red : .secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
