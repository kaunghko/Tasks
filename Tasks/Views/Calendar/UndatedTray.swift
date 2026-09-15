import SwiftUI

/// Open tasks without a due date. Drag them onto a day to schedule them,
/// or drop a dated task here to clear its date.
struct UndatedTray: View {
    @Binding var tasks: [TaskItem]
    let undated: [TaskItem]
    let selection: Set<TaskItem.ID>
    let actions: CalendarActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("No Due Date")
                .font(.headline)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(undated) { task in
                        TaskChip(
                            task: $tasks[id: task.id],
                            isSelected: selection.contains(task.id),
                            actions: actions
                        )
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: .infinity)
            .overlay {
                if undated.isEmpty {
                    Text("Drop a task here to clear its due date.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
        .frame(width: 200)
        .calendarDropTarget(day: nil, actions: actions)
    }
}
