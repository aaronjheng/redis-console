import SwiftUI

// MARK: - Function Stats View

struct FunctionStatsView: View {
    @Environment(ConnectionState.self) private var app

    private var isClusterMode: Bool {
        app.selectedConnection?.mode == .cluster || !app.clusterNodes.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = app.functionStatsError {
                ErrorBanner(message: error, dismissAction: { app.functionStatsError = nil })
                Divider()
            }

            if app.isFetchingFunctionStats && app.functionRunningScripts.isEmpty && app.functionEngineStats.isEmpty {
                Spacer()
                ProgressView("Loading function stats\u{2026}")
                    .controlSize(.small)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.large) {
                        runningScriptsCard
                        engineSummaryCard
                    }
                    .padding(AppSpacing.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task(id: app.functionStatsAutoRefresh) {
            await app.fetchFunctionStats()
            let interval = app.functionStatsAutoRefresh
            guard interval > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { break }
                await app.fetchFunctionStats()
            }
        }
    }

    // MARK: Running scripts

    private var runningScriptsCard: some View {
        Card(title: "Running Scripts") {
            if app.functionRunningScripts.isEmpty {
                Label("No scripts currently running", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(app.functionRunningScripts.enumerated()), id: \.element.id) { index, entry in
                        runningScriptRow(entry)
                        if index < app.functionRunningScripts.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func runningScriptRow(_ entry: RedisFunctionRunningScriptEntry) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack(spacing: AppSpacing.small) {
                Text(entry.script.name)
                    .font(AppFont.monoSubheadline)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                Text(entry.script.command)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(durationText(entry.script.durationMs))
                    .font(AppFont.monoSubheadline)
                    .foregroundStyle(durationColor(entry.script.durationMs))
            }
            HStack(spacing: AppSpacing.small) {
                if isClusterMode {
                    Badge(text: entry.node?.address ?? "-", systemImage: "server.rack")
                }
                if !entry.script.args.isEmpty {
                    Text(entry.script.args.joined(separator: " "))
                        .font(AppFont.monoCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, AppSpacing.small)
    }

    // MARK: Engine summary

    private var engineSummaryCard: some View {
        Card(title: "Engine Summary") {
            if app.functionEngineStats.isEmpty {
                Text("No engine data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(app.functionEngineStats.sorted(by: nodeOrder).enumerated()), id: \.element.key) { index, item in
                        engineStatsRow(node: item.key, stats: item.value)
                        if index < app.functionEngineStats.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func engineStatsRow(node: RedisEndpoint?, stats: RedisFunctionEngineStats) -> some View {
        HStack(spacing: AppSpacing.medium) {
            if isClusterMode {
                Badge(text: node?.address ?? "-", systemImage: "server.rack")
                    .frame(minWidth: 180, alignment: .leading)
            } else {
                Text("LUA")
                    .font(AppFont.monoSubheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statsLabel("Libraries", stats.librariesCount)
            statsLabel("Functions", stats.functionsCount)
        }
        .padding(.vertical, AppSpacing.small)
    }

    private func statsLabel(_ title: String, _ count: Int) -> some View {
        VStack(alignment: .trailing, spacing: AppSpacing.xxSmall) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(AppFont.monoSubheadline)
                .monospacedDigit()
        }
    }

    // MARK: Helpers

    /// Sorts nodes so standalone (nil) comes first, then by address.
    private func nodeOrder(
        _ lhs: (key: RedisEndpoint?, value: RedisFunctionEngineStats),
        _ rhs: (key: RedisEndpoint?, value: RedisFunctionEngineStats)
    ) -> Bool {
        switch (lhs.key, rhs.key) {
        case (nil, nil): return false
        case (nil, _): return true
        case (_, nil): return false
        case (let leftEndpoint?, let rightEndpoint?): return leftEndpoint.address < rightEndpoint.address
        }
    }

    private func durationText(_ ms: Int) -> String {
        if ms >= 1_000 {
            return String(format: "%.2f s", Double(ms) / 1_000)
        }
        return "\(ms) ms"
    }

    private func durationColor(_ ms: Int) -> Color {
        if ms >= 1_000 {
            return AppColor.error
        } else if ms >= 100 {
            return AppColor.warning
        }
        return .primary
    }
}
