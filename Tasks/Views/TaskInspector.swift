import SwiftUI

struct TaskInspector: View {
    @Binding var task: TaskItem

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $task.title, axis: .vertical)
                Toggle("Completed", isOn: $task.done)
            }

            Section {
                Toggle("Due Date", isOn: $task.hasDueDate)
                if task.hasDueDate {
                    DatePicker("Date", selection: $task.dueDay, displayedComponents: .date)
                }
            }

            Section("Notes") {
                TextEditor(text: $task.notes)
                    .font(.body)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
            }

            Section {
                LabeledContent(
                    "Created",
                    value: task.createdAt.formatted(date: .abbreviated, time: .shortened)
                )
            }
        }
        .formStyle(.grouped)
    }
}
