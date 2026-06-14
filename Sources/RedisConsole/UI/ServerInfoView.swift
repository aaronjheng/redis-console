import SwiftUI

struct ServerInfoView: View {
    @EnvironmentObject var app: ConnectionState

    var sections: [String] {
        app.serverInfo.keys.sorted()
    }

    private var isClusterMode: Bool {
        app.selectedConnection?.mode == .cluster || !app.clusterNodes.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Server Info")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await app.loadServerInfo() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding()

            if isClusterMode && !app.clusterNodes.isEmpty {
                clusterInfoView
            } else if app.serverInfo.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "info.circle",
                    title: "No server info loaded",
                    actionTitle: "Load Info",
                    action: { Task { await app.loadServerInfo() } }
                )
                Spacer()
            } else {
                serverInfoList
            }
        }
    }

    private var clusterInfoView: some View {
        VStack(spacing: 0) {
            clusterSummaryBar
            Divider()
            HStack(spacing: 0) {
                clusterNodeList
                    .frame(width: 280)
                Divider()
                VStack(spacing: 0) {
                    selectedNodeHeader
                    Divider()
                    serverInfoList
                }
            }
        }
    }

    private var clusterSummaryBar: some View {
        HStack(spacing: 24) {
            summaryItem("State", app.clusterInfo["cluster_state"] ?? "-")
            summaryItem("Nodes", app.clusterInfo["cluster_known_nodes"] ?? "\(app.clusterNodes.count)")
            summaryItem("Primaries", "\(app.clusterNodes.filter { $0.role == .primary }.count)")
            summaryItem("Replicas", "\(app.clusterNodes.filter { $0.role == .replica }.count)")
            summaryItem("Slots", app.clusterInfo["cluster_slots_assigned"] ?? "\(assignedSlotCount)")
            summaryItem("OK Slots", app.clusterInfo["cluster_slots_ok"] ?? "-")
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var clusterNodeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nodes")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(app.clusterNodes) { node in
                        Button {
                            Task { await app.selectServerInfoNode(node.endpoint) }
                        } label: {
                            clusterNodeRow(node)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .background(AppTheme.sidebarBackground)
    }

    private var selectedNodeHeader: some View {
        HStack(spacing: 12) {
            if let node = selectedNode {
                Image(systemName: node.role == .primary ? "server.rack" : "externaldrive.connected.to.line.below")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.endpoint.address)
                        .font(.headline)
                    Text(nodeSubtitle(node))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text("No node selected")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var serverInfoList: some View {
        List {
            ForEach(sections, id: \.self) { section in
                Section(header: Text(section)) {
                    if let items = app.serverInfo[section] {
                        ForEach(items.keys.sorted(), id: \.self) { key in
                            HStack {
                                Text(key)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 160, alignment: .leading)
                                Spacer()
                                Text(items[key] ?? "")
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var selectedNode: RedisClusterNodeSummary? {
        guard let endpoint = app.selectedServerInfoNode else { return nil }
        return app.clusterNodes.first { $0.endpoint == endpoint }
    }

    private var assignedSlotCount: Int {
        app.clusterNodes
            .filter { $0.role == .primary }
            .reduce(0) { $0 + $1.coveredSlotCount }
    }

    private func clusterNodeRow(_ node: RedisClusterNodeSummary) -> some View {
        let isSelected = app.selectedServerInfoNode == node.endpoint

        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: node.role == .primary ? "server.rack" : "externaldrive.connected.to.line.below")
                .frame(width: 16)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.endpoint.address)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(nodeSubtitle(node))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
    }

    private func summaryItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func nodeSubtitle(_ node: RedisClusterNodeSummary) -> String {
        switch node.role {
        case .primary:
            return "Primary · slots \(node.slotSummary)"
        case .replica:
            return "Replica of \(node.replicaOf?.address ?? "-")"
        }
    }
}
