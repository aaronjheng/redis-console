import SwiftUI

// MARK: - Slow Log View

struct SlowLogView: View {
    @Environment(TabState.self) private var tab
    @State private var filterText = ""

    private var filteredEntries: [SlowLogEntry] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return tab.slowLogEntries }
        return tab.slowLogEntries.filter { entry in
            entry.commandText.lowercased().contains(query)
                || entry.clientIP.lowercased().contains(query)
                || entry.clientName.lowercased().contains(query)
        }
    }

    var body: some View {
        @Bindable var tab = tab

        VStack(spacing: 0) {
            // Header
            HStack(spacing: AppSpacing.medium) {
                FilterField("Filter command, client, or name", text: $filterText)
                    .frame(maxWidth: .infinity)

                RefreshControl(
                    autoRefreshInterval: $tab.slowLogConfig.autoRefreshInterval,
                    isLoading: tab.isLoadingSlowLog,
                    intervals: SlowLogConfig.autoRefreshOptions.map(\.value)
                ) {
                    Task { await tab.fetchSlowLog() }
                }
            }
            .panelToolbar()

            Divider()

            if let error = tab.slowLogError {
                ErrorBanner(message: error, dismissAction: { tab.slowLogError = nil })
                Divider()
            }

            // Entries list
            if filteredEntries.isEmpty {
                Spacer()
                if tab.isLoadingSlowLog {
                    LoadingState(message: "Loading slow log…")
                } else if filterText.isEmpty {
                    ContentUnavailableView(
                        "No slow log entries",
                        systemImage: "hourglass",
                        description: Text(
                            "Queries slower than \(slowLogThresholdText) will appear here")
                    )
                    Button("Refresh") {
                        Task { await tab.fetchSlowLog() }
                    }
                    .padding(.top, AppSpacing.small)
                } else {
                    ContentUnavailableView(
                        "No matching entries",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different filter.")
                    )
                    Button("Clear Filter") {
                        filterText = ""
                    }
                    .padding(.top, AppSpacing.small)
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
            PanelFooterBar {
                StatusFooterView(
                    countText: footerCountText
                )
                Spacer()
            }
        }
        .task(id: tab.slowLogConfig.autoRefreshInterval) {
            // Fetch once, then keep the refresh loop alive while an interval
            // is set. Changing the interval restarts this task.
            await tab.fetchSlowLog()
            let interval = tab.slowLogConfig.autoRefreshInterval
            guard interval > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, !tab.isLoadingSlowLog else { continue }
                await tab.fetchSlowLog()
            }
        }
    }

    private var slowLogThresholdText: String {
        let micros = tab.slowLogConfig.threshold
        if micros >= 1_000_000 {
            return String(format: "%.1f s", Double(micros) / 1_000_000)
        } else if micros >= 1_000 {
            return String(format: "%.0f ms", Double(micros) / 1_000)
        }
        return "\(micros) µs"
    }

    private var footerCountText: String {
        let total = tab.slowLogEntries.count
        let filtered = filteredEntries.count
        if filterText.isEmpty || filtered == total {
            return "\(total) entries"
        }
        return "Showing \(filtered) of \(total) entries"
    }

    private func durationColor(_ duration: Int) -> Color {
        if duration >= 1_000_000 {
            return AppColor.error
        } else if duration >= 10_000 {
            return AppColor.warning
        }
        return .primary
    }

}
