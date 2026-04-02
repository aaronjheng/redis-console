import SwiftUI

struct CLIView: View {
    @EnvironmentObject var app: ConnectionState
    @State private var input = ""
    @State private var historyIndex = -1
    @State private var showCompletions = false
    @FocusState private var inputFocused: Bool

    var filteredCompletions: [String] {
        guard !input.isEmpty else { return [] }
        let parts = input.split(separator: " ")
        if parts.count <= 1 {
            return app.completions(for: String(parts.first ?? ""))
        }
        return []
    }

    var body: some View {
        VStack(spacing: 0) {
            // History list
            if app.cliHistory.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Enter Redis commands below")
                        .foregroundStyle(.secondary)
                    Text("Supports auto-complete, press Tab to complete")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(app.cliHistory) { entry in
                                CLIHistoryRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: app.cliHistory.count) { _, _ in
                        if let last = app.cliHistory.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Divider()

            // Completion suggestions
            if showCompletions && !filteredCompletions.isEmpty {
                HStack(spacing: 4) {
                    ForEach(filteredCompletions.prefix(10), id: \.self) { cmd in
                        Text(cmd)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .onTapGesture {
                                input = cmd + " "
                                showCompletions = false
                            }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            // Input area
            HStack(spacing: 8) {
                Text(">")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .bold()

                TextField("Enter command...", text: $input, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .focused($inputFocused)
                    .onSubmit { executeCommand() }
                    .onChange(of: input) { _, newValue in
                        showCompletions = !newValue.isEmpty
                    }
                    .onKeyPress(.tab) {
                        if let firstCompletion = filteredCompletions.first {
                            input = firstCompletion + " "
                            showCompletions = false
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.upArrow) {
                        if !app.cliHistory.isEmpty {
                            historyIndex = min(historyIndex + 1, app.cliHistory.count - 1)
                            input = app.cliHistory[app.cliHistory.count - 1 - historyIndex].command
                        }
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        if historyIndex > 0 {
                            historyIndex -= 1
                            input = app.cliHistory[app.cliHistory.count - 1 - historyIndex].command
                        } else if historyIndex == 0 {
                            historyIndex = -1
                            input = ""
                        }
                        return .handled
                    }

                Button(action: executeCommand) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(input.isEmpty)
            }
            .padding()
            .background(.bar)
        }
        .onAppear { inputFocused = true }
    }

    private func executeCommand() {
        let cmd = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        historyIndex = -1
        showCompletions = false
        input = ""
        Task { await app.executeCommand(cmd) }
    }
}

struct CLIHistoryRow: View {
    let entry: CLIHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("> \(entry.command)")
                    .font(.system(.body, design: .monospaced))
                    .bold()
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(entry.result)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(entry.isError ? .red : .primary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(entry.isError ? Color.red.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}
