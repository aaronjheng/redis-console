import SwiftUI

struct ShellView: View {
    @Environment(ConnectionState.self) private var app
    @State private var input = ""
    @State private var historyIndex = -1
    @State private var showCompletions = false
    @State private var showDangerousCommandAlert = false
    @State private var pendingCommand = ""
    @FocusState private var inputFocused: Bool

    private let dangerousCommands: Set<String> = [
        "FLUSHDB", "FLUSHALL", "FLUSHDB ASYNC", "FLUSHALL ASYNC", "KEYS", "KEYS *", "DEBUG", "SHUTDOWN", "SLAVEOF", "REPLICAOF",
        "CONFIG RESETSTAT", "BGREWRITEAOF", "BGSAVE", "SAVE", "LASTSAVE", "MONITOR", "SYNC", "PSYNC", "CLIENT PAUSE",
        "DEBUG SET-ACTIVE-EXPIRE", "MIGRATE", "RESTORE", "SORT", "EVAL", "EVALSHA", "SCRIPT", "ACL", "AUTH", "ROLE", "SWAPDB", "MOVE",
        "RENAME", "RENAMENX", "DEL", "UNLINK", "WAIT", "REPLCONF", "PING", "ECHO", "QUIT", "SELECT",
    ]

    private let criticalDangerousCommands: Set<String> = [
        "FLUSHDB", "FLUSHALL", "FLUSHDB ASYNC", "FLUSHALL ASYNC", "SHUTDOWN", "DEBUG", "SLAVEOF", "REPLICAOF", "CONFIG RESETSTAT", "SWAPDB",
        "MOVE",
    ]

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
                ContentUnavailableView(
                    "Enter Redis commands below",
                    systemImage: "terminal",
                    description: Text("Supports auto-complete, press Tab to complete")
                )
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(app.shellHistory) { entry in
                                ShellHistoryRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
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

            // Input area — Grok-style pill composer
            VStack(spacing: AppSpacing.xSmall) {
                if showCompletions && !filteredCompletions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.xSmall) {
                            ForEach(filteredCompletions.prefix(12), id: \.self) { cmd in
                                Button {
                                    input = cmd + " "
                                    showCompletions = false
                                } label: {
                                    Text(cmd)
                                        .font(.subheadline)
                                        .padding(.horizontal, AppSpacing.small)
                                        .padding(.vertical, AppSpacing.xxSmall)
                                        .background(Color.secondary.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, AppSpacing.large)
                    }
                }

                HStack(spacing: AppSpacing.small) {
                    Text("›")
                        .font(AppFont.dataCell)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColor.terminalPrompt)

                    TextField("Send a Redis command", text: $input, axis: .vertical)
                        .font(AppFont.monoBody)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
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
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(input.isEmpty ? Color.secondary : Color(.controlBackgroundColor))
                            .frame(width: 30, height: 30)
                            .background(input.isEmpty ? Color.secondary.opacity(0.18) : Color.primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(input.isEmpty)
                }
                .padding(.horizontal, AppSpacing.medium)
                .padding(.vertical, AppSpacing.small)
                .background(
                    Capsule()
                        .fill(.background)
                        .overlay(Capsule().stroke(Color.secondary.opacity(0.18), lineWidth: 1))
                )
                .padding(.horizontal, AppSpacing.large)
                .padding(.vertical, AppSpacing.small)
            }
            .background(.bar)

            Divider()
            WorkspaceFooterBar {
                StatusFooterView(countText: "\(app.shellHistory.count) commands")
                Spacer()
            }
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

    private var statusColor: Color {
        entry.isError ? AppColor.terminalError : AppColor.terminalSuccess
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            // Command line: prompt + highlighted command + status + time
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                Text("›")
                    .font(AppFont.dataCell)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColor.terminalPrompt.opacity(0.65))

                Text(ShellSyntaxHighlighter.highlight(entry.command))
                    .font(AppFont.dataCell)
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: entry.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(statusColor)

                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Output block
            Text(entry.result)
                .font(AppFont.monoSubheadline)
                .foregroundStyle(entry.isError ? AppColor.terminalError : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.small)
                .background(AppColor.terminalOutputBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
        }
        .padding(.horizontal, AppSpacing.large)
        .padding(.vertical, AppSpacing.medium)
        .background(.background)
    }
}
