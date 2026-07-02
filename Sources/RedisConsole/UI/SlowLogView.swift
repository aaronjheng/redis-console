import SwiftUI

// MARK: - Slow Log View

struct SlowLogView: View {
    @Environment(ConnectionState.self) private var app

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Slow Log")
                    .font(.headline)
                Spacer()
                RefreshControl(
                    autoRefreshInterval: $app.slowLogConfig.autoRefreshInterval,
                    isLoading: app.isLoadingSlowLog,
                    intervals: [5, 10, 30, 60],
                    onRefresh: { Task { await app.fetchSlowLog() } }
                )

            }
            .padding(AppTheme.spacingLarge)

            // Entries list
            if app.slowLogEntries.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No slow log entries",
                    systemImage: "tortoise",
                    description: Text("Slow queries will appear here")
                )
                Spacer()
            } else {
                Table(app.slowLogEntries) {
                    TableColumn("ID") { entry in
                        Text("#\(entry.id)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .width(60)

                    TableColumn("Duration") { entry in
                        Text(entry.durationText)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(durationColor(entry.duration))
                    }
                    .width(90)

                    TableColumn("Time") { entry in
                        Text(entry.timestamp, style: .time)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .width(70)

                    TableColumn("Command") { entry in
                        Text(entry.commandText)
                            .font(.system(.subheadline, design: .monospaced))
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }

                    TableColumn("Client") { entry in
                        Text(entry.clientIP)
                            .font(.subheadline)
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
            await app.fetchSlowLog()
        }
        .onChange(of: app.slowLogConfig.autoRefreshInterval) { _, _ in
            app.saveSlowLogConfig()
        }
        .task(id: app.slowLogConfig.autoRefreshInterval) {
            await autoRefreshSlowLog(interval: app.slowLogConfig.autoRefreshInterval)
        }
    }

    private func durationColor(_ duration: Int) -> Color {
        if duration >= 1_000_000 {
            return DomainColor.statusError
        } else if duration >= 100_000 {
            return DomainColor.statusWarning
        } else if duration >= 10_000 {
            return DomainColor.statusWarning
        }
        return .primary
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
