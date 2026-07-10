import SwiftUI

// MARK: - Slow Log View

struct SlowLogView: View {
    @Environment(ConnectionState.self) private var app
    @State private var filterText = ""

    private var filteredEntries: [SlowLogEntry] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return app.slowLogEntries }
        return app.slowLogEntries.filter { entry in
            entry.commandText.lowercased().contains(query)
                || entry.clientIP.lowercased().contains(query)
                || entry.clientName.lowercased().contains(query)
        }
    }

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 0) {
            // Header
            HStack(spacing: AppSpacing.medium) {
                ZStack(alignment: .trailing) {
                    TextField("Filter command, client, or name", text: $filterText)
                        .textFieldStyle(.roundedBorder)

                    if !filterText.isEmpty {
                        Button("Clear Filter", systemImage: "xmark.circle.fill") {
                            filterText = ""
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)
                    }
                }
                .frame(maxWidth: 360)

                Spacer()

                RefreshControl(
                    autoRefreshInterval: $app.slowLogConfig.autoRefreshInterval,
                    isLoading: app.isLoadingSlowLog,
                    intervals: [5, 10, 30, 60],
                    onRefresh: { Task { await app.fetchSlowLog() } }
                )
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.small)

            Divider()

            // Entries list
            if filteredEntries.isEmpty {
                Spacer()
                if app.isLoadingSlowLog {
                    ProgressView("Loading slow log...")
                        .controlSize(.small)
                } else {
                    ContentUnavailableView(
                        "No slow log entries",
                        systemImage: "tortoise",
                        description: Text("Slow queries will appear here")
                    )
                }
                Spacer()
            } else {
                Table(filteredEntries) {
                    TableColumn("ID") { entry in
                        Text("#\(entry.id)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .width(60)

                    TableColumn("Duration") { entry in
                        Text(entry.durationText)
                            .font(AppFont.monoSubheadline)
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
                            .font(AppFont.monoSubheadline)
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
            }

            Divider()

            // Footer
            WorkspaceFooterBar {
                StatusFooterView(
                    countText: footerCountText
                )
                Spacer()
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

    private var footerCountText: String {
        let total = app.slowLogEntries.count
        let filtered = filteredEntries.count
        if filterText.isEmpty || filtered == total {
            return "\(total) entries total"
        }
        return "\(filtered) of \(total) entries"
    }

    private func durationColor(_ duration: Int) -> Color {
        if duration >= 1_000_000 {
            return AppColor.error
        } else if duration >= 100_000 {
            return AppColor.warning
        } else if duration >= 10_000 {
            return AppColor.warning
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
