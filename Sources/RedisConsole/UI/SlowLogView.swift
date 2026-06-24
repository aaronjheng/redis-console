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
                SlowLogRefreshControl(
                    autoRefreshInterval: $app.slowLogConfig.autoRefreshInterval,
                    isLoading: app.isLoadingSlowLog,
                    onRefresh: { Task { await app.fetchSlowLog() } }
                )

            }
            .padding()

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
            return .red
        } else if duration >= 100_000 {
            return .orange
        } else if duration >= 10_000 {
            return .yellow
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

// MARK: - Slow Log Refresh Control

private struct SlowLogRefreshControl: View {
    @Binding var autoRefreshInterval: TimeInterval
    let isLoading: Bool
    let onRefresh: () -> Void

    private static let intervals: [TimeInterval] = [5, 10, 30, 60]

    private var isAutoRefreshEnabled: Bool {
        autoRefreshInterval > 0
    }

    private static func intervalTitle(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s.isMultiple(of: 60) {
            return "\(s / 60)m"
        }
        return "\(s)s"
    }

    @State private var isRefreshHovering = false
    @State private var isMenuHovering = false

    var body: some View {
        HStack(spacing: 0) {
            refreshButton
            separator
            intervalMenu
        }
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .opacity(isLoading ? 0.5 : 1)
    }

    private var refreshButton: some View {
        Button {
            onRefresh()
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
                .background(
                    isRefreshHovering && !isLoading
                        ? Color.primary.opacity(0.08)
                        : Color.clear
                )
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 6,
                        bottomLeadingRadius: 6,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { isRefreshHovering = $0 }
        .help("Refresh")
    }

    private var separator: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 0.5, height: 14)
    }

    private var intervalMenu: some View {
        Menu {
            Button {
                autoRefreshInterval = 0
            } label: {
                menuItemLabel(text: "Off", checked: !isAutoRefreshEnabled)
            }
            Divider()
            ForEach(Self.intervals, id: \.self) { interval in
                Button {
                    autoRefreshInterval = interval
                } label: {
                    menuItemLabel(
                        text: Self.intervalTitle(interval),
                        checked: isAutoRefreshEnabled && autoRefreshInterval == interval
                    )
                }
            }
        } label: {
            HStack(spacing: 0) {
                if isAutoRefreshEnabled {
                    Text(Self.intervalTitle(autoRefreshInterval))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 6)
                } else {
                    Color.clear.frame(width: 18, height: 22)
                }
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .background(
                isMenuHovering && !isLoading
                    ? Color.primary.opacity(0.08)
                    : Color.clear
            )
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 6,
                    topTrailingRadius: 6,
                    style: .continuous
                )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .disabled(isLoading)
        .onHover { isMenuHovering = $0 }
        .help(isAutoRefreshEnabled ? "Auto refresh every \(Self.intervalTitle(autoRefreshInterval))" : "Auto refresh off")
    }

    private func menuItemLabel(text: String, checked: Bool) -> some View {
        Text(checked ? "\(text)  \u{2713}" : text)
    }
}
