import SwiftUI

struct ShellView: View {
    @Environment(TabState.self) private var tab
    @State private var input = ""
    @State private var historyIndex = -1
    @State private var historyDraft = ""
    @State private var showCompletions = false
    @State private var showDangerousCommandAlert = false
    @State private var showProductionConfirm = false
    @State private var productionConfirmText = ""
    @State private var pendingCommand = ""
    @FocusState private var inputFocused: Bool

    /// Commands that require confirmation only in production environments.
    private let productionConfirmCommands: Set<String> = [
        "FLUSHDB", "FLUSHALL", "FLUSHDB ASYNC", "FLUSHALL ASYNC", "SHUTDOWN", "DEBUG", "SLAVEOF", "REPLICAOF", "CONFIG RESETSTAT", "SWAPDB",
        "MOVE",
    ]

    /// Commands that require confirmation in ALL environments, including non-production.
    /// Key deletes always confirm, matching the Browser delete flow.
    private let alwaysConfirmCommands: Set<String> = [
        "FLUSHDB", "FLUSHALL", "FLUSHDB ASYNC", "FLUSHALL ASYNC", "SHUTDOWN", "SWAPDB",
        "DEL", "UNLINK",
    ]

    var filteredCompletions: [String] {
        guard !input.isEmpty else { return [] }
        let parts = input.split(separator: " ")
        if parts.count <= 1 {
            return tab.completions(for: String(parts.first ?? ""))
        }
        return []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            VStack(spacing: 0) {
                HStack(spacing: AppSpacing.medium) {
                    Spacer()
                    Button(
                        action: { tab.clearShellHistory() },
                        label: {
                            Label("Clear", systemImage: "trash")
                        }
                    )
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(tab.shellHistory.isEmpty)
                }
                .panelToolbar()

                Divider()
            }

            // History list
            if tab.shellHistory.isEmpty {
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
                            ForEach(tab.shellHistory) { entry in
                                ShellHistoryRow(entry: entry)
                                    .id(entry.id)
                                    .contextMenu {
                                        Button("Copy Command") {
                                            copyToPasteboard(entry.command)
                                        }
                                        Button("Copy Result") {
                                            copyToPasteboard(entry.result)
                                        }
                                        Divider()
                                        Button("Delete", role: .destructive) {
                                            tab.deleteShellHistoryEntry(entry)
                                        }
                                    }
                            }
                        }
                    }
                    .onChange(of: tab.shellHistory.count) { _, _ in
                        if let last = tab.shellHistory.last {
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
                    ScrollView(.horizontal) {
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
                                        .background(AppColor.subtleBackground)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, AppSpacing.large)
                    }
                    .scrollIndicators(.hidden)
                }

                HStack(spacing: AppSpacing.small) {
                    Text("›")
                        .font(AppFont.dataCell)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColor.shellPrompt)

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
                        .onKeyPress(.escape) {
                            if showCompletions {
                                showCompletions = false
                                return .handled
                            }
                            return .ignored
                        }
                        .onKeyPress(.upArrow) {
                            if !tab.shellHistory.isEmpty {
                                if historyIndex == -1 {
                                    historyDraft = input
                                }
                                historyIndex = min(historyIndex + 1, tab.shellHistory.count - 1)
                                input = tab.shellHistory[tab.shellHistory.count - 1 - historyIndex].command
                            }
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            if historyIndex > 0 {
                                historyIndex -= 1
                                input = tab.shellHistory[tab.shellHistory.count - 1 - historyIndex].command
                            } else if historyIndex == 0 {
                                historyIndex = -1
                                input = historyDraft
                            }
                            return .handled
                        }

                    Button(action: executeCommand) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(input.isEmpty ? .secondary : Color(.controlBackgroundColor))
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
                    RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                        .fill(.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                )
                .padding(.horizontal, AppSpacing.large)
                .padding(.vertical, AppSpacing.small)
            }
            .background(.bar)

            Divider()
            PanelFooterBar {
                StatusFooterView(countText: "\(tab.shellHistory.count) commands")
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
                Task { await tab.executeCommand(cmd) }
            }
        } message: {
            if tab.selectedConnection?.environment == .production {
                Text("This is a PRODUCTION database. Are you sure you want to execute:\n\n\(pendingCommand)")
            } else {
                Text("This command is potentially destructive. Are you sure you want to execute:\n\n\(pendingCommand)")
            }
        }
        .sheet(isPresented: $showProductionConfirm) {
            ProductionConfirmView(
                title: "Execute on Production?",
                message: "This will execute the following command on a production"
                    + "server. This action cannot be undone.\n\n\(pendingCommand)",
                confirmText: "EXECUTE",
                confirmButtonTitle: "Execute",
                input: $productionConfirmText,
                onConfirm: {
                    input = ""
                    let cmd = pendingCommand
                    pendingCommand = ""
                    productionConfirmText = ""
                    showProductionConfirm = false
                    Task { await tab.executeCommand(cmd) }
                },
                onCancel: {
                    pendingCommand = ""
                    productionConfirmText = ""
                    showProductionConfirm = false
                }
            )
            .presentationSizing(.form)
        }
    }

    private func executeCommand() {
        let cmd = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        historyIndex = -1
        historyDraft = ""
        showCompletions = false

        let cmdUpper = cmd.uppercased().trimmingCharacters(in: .whitespaces)
        let isProduction = tab.selectedConnection?.environment == .production
        let isAlwaysConfirm = alwaysConfirmCommands.contains { cmdUpper.hasPrefix($0) }
        let isProductionOnly = productionConfirmCommands.contains { cmdUpper.hasPrefix($0) }

        if isAlwaysConfirm || (isProductionOnly && isProduction) {
            pendingCommand = cmd
            if isProduction {
                showProductionConfirm = true
            } else {
                showDangerousCommandAlert = true
            }
            return
        }

        input = ""
        Task { await tab.executeCommand(cmd) }
    }
}

struct ShellHistoryRow: View, Equatable {
    let entry: ShellHistoryEntry

    /// Without `Equatable`, SwiftUI re-evaluates every history row's body on
    /// each keystroke in the input field; this lets unchanged rows skip their
    /// body (and the highlighter call) entirely.
    static nonisolated func == (lhs: ShellHistoryRow, rhs: ShellHistoryRow) -> Bool {
        lhs.entry == rhs.entry
    }

    private var statusColor: Color {
        entry.isError ? AppColor.shellError : AppColor.shellSuccess
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            // Command line: prompt + highlighted command + status + time
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                Text("›")
                    .font(AppFont.dataCell)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColor.shellPrompt.opacity(0.65))

                Text(TreeSitterBashHighlighter.shared.highlight(entry.command))
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
                .foregroundStyle(entry.isError ? AppColor.shellError : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.small)
                .background(AppColor.shellOutputBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
        }
        .padding(.horizontal, AppSpacing.large)
        .padding(.vertical, AppSpacing.small)
        .background(.background)
    }
}
