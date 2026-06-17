import SwiftUI

// MARK: - Slow Log View

struct SlowLogView: View {
    @Environment(ConnectionState.self) private var app
    @State private var showClearConfirmation = false
    @State private var thresholdUnit = 1
    @State private var isApplyingSlowLogConfig = false

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Slow Log")
                    .font(.headline)
                Spacer()
                if app.isLoadingSlowLog {
                    ProgressView()
                        .scaleEffect(0.7)
                        .controlSize(.small)
                }
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await app.fetchSlowLog() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(app.isLoadingSlowLog)
                .help("Refresh")

                Button("Clear Slow Log", systemImage: "trash") {
                    showClearConfirmation = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(app.slowLogEntries.isEmpty)
                .help("Clear Slow Log")
            }
            .padding()

            Divider()

            // Config bar
            HStack(spacing: AppTheme.spacing) {
                HStack(spacing: 4) {
                    Text("Threshold:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", value: thresholdValue, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .font(.caption)
                        .onSubmit {
                            Task { await applySlowLogConfig() }
                        }
                    Picker("", selection: thresholdUnitSelection) {
                        Text("\u{00B5}s").tag(1)
                        Text("ms").tag(1000)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 80)
                }

                HStack(spacing: 4) {
                    Text("Max Len:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", value: $app.slowLogConfig.maxLen, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .font(.caption)
                        .onSubmit {
                            Task { await applySlowLogConfig() }
                        }
                }

                Button("Apply", systemImage: "checkmark.circle") {
                    Task { await applySlowLogConfig() }
                }
                .font(.caption)
                .disabled(isApplyingSlowLogConfig || app.activeClient?.isConnected != true)

                HStack(spacing: 4) {
                    Text("Auto-refresh:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $app.slowLogConfig.autoRefreshInterval) {
                        ForEach(SlowLogConfig.autoRefreshOptions, id: \.value) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 60)
                }

                Spacer()

                if let error = app.slowLogError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            // Entries list
            if app.slowLogEntries.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "tortoise",
                    title: "No slow log entries",
                    subtitle: "Slow queries will appear here"
                )
                Spacer()
            } else {
                Table(app.slowLogEntries) {
                    TableColumn("ID") { entry in
                        Text("#\(entry.id)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .width(60)

                    TableColumn("Duration") { entry in
                        Text(entry.durationText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(durationColor(entry.duration))
                    }
                    .width(90)

                    TableColumn("Time") { entry in
                        Text(entry.timestamp, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(70)

                    TableColumn("Command") { entry in
                        Text(entry.commandText)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }

                    TableColumn("Client") { entry in
                        Text(entry.clientIP)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(130)
                }
                .tableStyle(.inset)

                // Footer
                WorkspaceFooterBar {
                    StatusFooterView(
                        countText: "\(app.slowLogEntries.count) entries total"
                    )
                    Spacer()
                }
            }
        }
        .task {
            app.loadSlowLogConfig()
            thresholdUnit = app.slowLogConfig.threshold >= 1000 ? 1000 : 1
            await app.fetchSlowLog()
        }
        .onChange(of: app.slowLogConfig.autoRefreshInterval) { _, _ in
            app.saveSlowLogConfig()
        }
        .task(id: app.slowLogConfig.autoRefreshInterval) {
            await autoRefreshSlowLog(interval: app.slowLogConfig.autoRefreshInterval)
        }
        .alert("Clear Slow Log?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task { await app.resetSlowLog() }
            }
        } message: {
            Text("This will remove all slow log entries. Continue?")
        }
    }

    private var thresholdUnitSelection: Binding<Int> {
        Binding(
            get: { thresholdUnit },
            set: { thresholdUnit = $0 }
        )
    }

    private var thresholdValue: Binding<Int> {
        Binding(
            get: { max(1, app.slowLogConfig.threshold / thresholdUnit) },
            set: { app.slowLogConfig.threshold = max(1, $0) * thresholdUnit }
        )
    }

    private func durationColor(_ duration: Int) -> Color {
        if duration >= 1_000_000 {
            return .red
        } else if duration >= 100_000 {
            return .orange
        } else if duration >= 10_000 {
            return .yellow
        }
        return .primary
    }

    @MainActor
    private func applySlowLogConfig() async {
        guard !isApplyingSlowLogConfig else { return }
        let threshold = app.slowLogConfig.threshold
        let maxLen = app.slowLogConfig.maxLen

        isApplyingSlowLogConfig = true
        defer { isApplyingSlowLogConfig = false }

        await app.updateSlowLogThreshold(threshold)
        await app.updateSlowLogMaxLen(maxLen)
        await app.fetchSlowLog()
    }

    private func autoRefreshSlowLog(interval: TimeInterval) async {
        guard interval > 0 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            await app.fetchSlowLog()
        }
    }
}
