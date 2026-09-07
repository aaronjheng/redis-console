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

                if tab.isLoadingSlowLog {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    Task { await tab.fetchSlowLog() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(tab.isLoadingSlowLog)
            }
            .panelToolbar()

            Divider()

            // Entries list
            if filteredEntries.isEmpty {
                Spacer()
                if tab.isLoadingSlowLog {
                    LoadingState(message: "Loading slow log...")
                } else {
                    ContentUnavailableView(
                        "No slow log entries",
                        systemImage: "hourglass",
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
            PanelFooterBar {
                StatusFooterView(
                    countText: footerCountText
                )
                Spacer()
            }
        }
        .task {
            await tab.fetchSlowLog()
        }
    }

    private var footerCountText: String {
        let total = tab.slowLogEntries.count
        let filtered = filteredEntries.count
        if filterText.isEmpty || filtered == total {
            return "\(total) entries total"
        }
        return "\(filtered) of \(total) entries"
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
