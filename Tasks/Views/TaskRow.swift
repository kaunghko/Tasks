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
