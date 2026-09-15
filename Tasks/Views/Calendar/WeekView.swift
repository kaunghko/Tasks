import SwiftUI

struct WeekView: View {
    let visibleDate: Date
    @Binding var tasks: [TaskItem]
    let tasksByDay: [Date: [TaskItem]]
    let selection: Set<TaskItem.ID>
    let actions: CalendarActions

    var body: some View {
        let days = CalendarGrid.weekDays(containing: visibleDate)

        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                if index > 0 {
                    Rectangle().fill(.separator).frame(width: 1)
                }
                column(for: day)
            }
        }
    }

    private func column(for day: Date) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(day, format: .dateTime.weekday(.abbreviated))
                    .foregroundStyle(.secondary)
                DayNumber(day: day)
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(tasksByDay[day] ?? []) { task in
                        TaskChip(
                            task: $tasks[id: task.id],
                            isSelected: selection.contains(task.id),
                            actions: actions
                        )
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .calendarDropTarget(day: day, actions: actions)
    }
}
