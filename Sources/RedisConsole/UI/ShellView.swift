import SwiftUI

struct ShellView: View {
    @EnvironmentObject var app: ConnectionState
    @State private var input = ""
    @State private var historyIndex = -1
    @State private var showCompletions = false
    @State private var showDangerousCommandAlert = false
    @State private var pendingCommand = ""
    @FocusState private var inputFocused: Bool

    private let dangerousCommands: Set<String> = ["FLUSHDB", "FLUSHALL", "FLUSHDB ASYNC", "FLUSHALL ASYNC", "KEYS", "KEYS *", "DEBUG", "SHUTDOWN", "SLAVEOF", "REPLICAOF", "CONFIG RESETSTAT", "BGREWRITEAOF", "BGSAVE", "SAVE", "LASTSAVE", "MONITOR", "SYNC", "PSYNC", "CLIENT PAUSE", "DEBUG SET-ACTIVE-EXPIRE", "MIGRATE", "RESTORE", "SORT", "EVAL", "EVALSHA", "SCRIPT", "ACL", "AUTH", "ROLE", "SWAPDB", "MOVE", "RENAME", "RENAMENX", "DEL", "UNLINK", "WAIT", "REPLCONF", "PING", "ECHO", "QUIT", "SELECT"]

    private let criticalDangerousCommands: Set<String> = ["FLUSHDB", "FLUSHALL", "FLUSHDB ASYNC", "FLUSHALL ASYNC", "SHUTDOWN", "DEBUG", "SLAVEOF", "REPLICAOF", "CONFIG RESETSTAT", "SWAPDB", "MOVE"]

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
            if app.shellHistory.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "terminal",
                    title: "Enter Redis commands below",
                    subtitle: "Supports auto-complete, press Tab to complete"
                )
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(app.shellHistory) { entry in
                                ShellHistoryRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: app.shellHistory.count) { _, _ in
                        if let last = app.shellHistory.last {
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
                        if !app.shellHistory.isEmpty {
                            historyIndex = min(historyIndex + 1, app.shellHistory.count - 1)
                            input = app.shellHistory[app.shellHistory.count - 1 - historyIndex].command
                        }
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        if historyIndex > 0 {
                            historyIndex -= 1
                            input = app.shellHistory[app.shellHistory.count - 1 - historyIndex].command
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
        .alert("Dangerous Command", isPresented: $showDangerousCommandAlert) {
            Button("Cancel", role: .cancel) {
                pendingCommand = ""
            }
            Button("Execute", role: .destructive) {
                input = ""
                let cmd = pendingCommand
                pendingCommand = ""
                Task { await app.executeCommand(cmd) }
            }
        } message: {
            Text("This is a PRODUCTION database. Are you sure you want to execute:\n\n\(pendingCommand)")
        }
    }

    private func executeCommand() {
        let cmd = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        historyIndex = -1
        showCompletions = false

        let cmdUpper = cmd.uppercased().trimmingCharacters(in: .whitespaces)
        let isDangerous = criticalDangerousCommands.contains { cmdUpper.hasPrefix($0) }

        if isDangerous && app.selectedConnection?.environment == .production {
            pendingCommand = cmd
            showDangerousCommandAlert = true
            return
        }

        input = ""
        Task { await app.executeCommand(cmd) }
    }
}

struct ShellHistoryRow: View {
    let entry: ShellHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("> ")
                    .font(.system(.body, design: .monospaced))
                    .bold()
                    .foregroundStyle(Color.accentColor)
                + Text(ShellSyntaxHighlighter.highlight(entry.command))
                    .font(.system(.body, design: .monospaced))
                    .bold()
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
