import SwiftUI

/// The ⌘K palette. Typing searches tasks and views; Tab narrows to tasks, a leading @ to views.
struct SearchPaletteView: View {
    let tasks: [TaskItem]
    let onChoose: (PaletteResult) -> Void
    let onDismiss: () -> Void

    @State private var text = ""
    @State private var lockedScope: PaletteScope = .mixed
    @State private var highlighted = 0
    @FocusState private var isFieldFocused: Bool

    private static let rowHeight: CGFloat = 28
    private static let rowSpacing: CGFloat = 2

    var body: some View {
        let query = PaletteQuery.parse(text, lockedScope: lockedScope)
        let results = SearchPalette.results(for: query, tasks: tasks)

        ZStack(alignment: .top) {
            Color.black.opacity(0.12)
                .contentShape(.rect)
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                field(results: results)
                if !results.isEmpty {
                    Divider()
                    resultList(results)
                } else if !query.term.isEmpty {
                    Divider()
                    Text("No Results")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                Divider()
                footer
            }
            .frame(width: 560)
            .background(.background, in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(.separator)
            }
            .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
            .padding(.top, 48)
        }
        .onExitCommand(perform: onDismiss)
        .onAppear { isFieldFocused = true }
        .onChange(of: text) { _, newValue in
            // A leading @ becomes a scope token, the same way Tab does for tasks.
            if lockedScope == .mixed, newValue.hasPrefix("@") {
                lockedScope = .views
                text = String(newValue.dropFirst())
            }
            highlighted = 0
        }
        .onChange(of: lockedScope) { highlighted = 0 }
    }

    // MARK: - Pieces

    private func field(results: [PaletteResult]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            if let title = lockedScope.title {
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 4))
            }
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isFieldFocused)
                .onSubmit {
                    guard results.indices.contains(highlighted) else { return }
                    onChoose(results[highlighted])
                }
                .onKeyPress(.upArrow) { move(by: -1, count: results.count) }
                .onKeyPress(.downArrow) { move(by: 1, count: results.count) }
                .onKeyPress(.tab) {
                    lockedScope = .tasks
                    return .handled
                }
                .onKeyPress(.delete) {
                    guard text.isEmpty, lockedScope != .mixed else { return .ignored }
                    lockedScope = .mixed
                    return .handled
                }
                .onKeyPress(.escape) {
                    onDismiss()
                    return .handled
                }
        }
        .padding(12)
    }

    private func resultList(_ results: [PaletteResult]) -> some View {
        let contentHeight = CGFloat(results.count) * (Self.rowHeight + Self.rowSpacing) + 10
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Self.rowSpacing) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        // No `.id(index)` here: it would override the ForEach identity, so rows at the
                        // same position kept showing the previous results' titles after typing.
                        row(result, isHighlighted: index == highlighted)
                            .onTapGesture { onChoose(result) }
                    }
                }
                .padding(6)
            }
            .frame(height: min(contentHeight, 340))
            .onChange(of: highlighted) { _, index in
                guard results.indices.contains(index) else { return }
                proxy.scrollTo(results[index].id)
            }
        }
    }

    private func row(_ result: PaletteResult, isHighlighted: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon(for: result))
                .frame(width: 18)
            Text(result.title)
                .lineLimit(1)
                .strikethrough(result.isDone)
            Spacer()
            if let detail = detail(for: result) {
                Text(detail)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(isHighlighted ? Color.white.opacity(0.85) : .secondary)
            }
        }
        .foregroundStyle(isHighlighted ? Color.white : result.isDone ? .secondary : .primary)
        .padding(.horizontal, 8)
        .frame(height: Self.rowHeight)
        .background(isHighlighted ? Color.accentColor : .clear, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("⇥", "Tasks")
            hint("@", "Views")
            hint("↑↓", "Move")
            hint("↩", "Open")
            Spacer()
            hint("esc", "Close")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        Text("\(Text(key).fontWeight(.semibold)) \(label)")
    }

    // MARK: - Helpers

    private var prompt: String {
        switch lockedScope {
        case .mixed: "Search tasks and views"
        case .tasks: "Search tasks"
        case .views: "Search views"
        }
    }

    private func icon(for result: PaletteResult) -> String {
        switch result {
        case .view(let view): view.systemImage
        case .task(let task): task.done ? "checkmark.circle.fill" : "circle"
        }
    }

    private func detail(for result: PaletteResult) -> String? {
        switch result {
        case .view(let view): view.subtitle
        case .task(let task):
            // The list the task lives in, then its date: "Upcoming · Sep 20".
            [TaskFilter.home(for: task).title, task.due?.formatted(.dateTime.month(.abbreviated).day())]
                .compactMap { $0 }
                .joined(separator: " · ")
        }
    }

    private func move(by offset: Int, count: Int) -> KeyPress.Result {
        guard count > 0 else { return .ignored }
        highlighted = min(max(highlighted + offset, 0), count - 1)
        return .handled
    }
}

private extension PaletteResult {
    var isDone: Bool {
        if case .task(let task) = self { task.done } else { false }
    }
}
