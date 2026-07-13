import SwiftUI

struct ServerInfoView: View {
    @Environment(ConnectionState.self) private var app

    var sections: [String] {
        app.serverInfo.keys
            .filter { $0 != "Modules" }
            .sorted()
    }

    @State private var showTopology = false

    private var isClusterMode: Bool {
        app.selectedConnection?.mode == .cluster || !app.clusterNodes.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: AppSpacing.medium) {
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await app.loadServerInfo() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Refresh")
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.small)

            Divider()

            if isClusterMode && !app.clusterNodes.isEmpty {
                clusterInfoView
            } else if app.serverInfo.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No server info loaded",
                    systemImage: "info.circle"
                )
                Button("Load Info") {
                    Task { await app.loadServerInfo() }
                }
                .padding(.top, 8)
                Spacer()
            } else {
                serverInfoList
            }
            Divider()
            WorkspaceFooterBar {
                StatusFooterView(countText: "\(sections.count) sections")
                if !app.serverCapabilities.isEmpty {
                    Text("·")
                    Text("\(app.serverCapabilities.count) modules")
                }
                Spacer()
            }
        }
    }

    private var clusterInfoView: some View {
        @Bindable var app = app

        return VStack(spacing: 0) {
            clusterSummaryBar
            Divider()
            HStack(spacing: 0) {
                if showTopology {
                    ClusterTopologyView(
                        nodes: app.clusterNodes,
                        selectedEndpoint: $app.selectedServerInfoNode,
                        onSelectNode: { endpoint in
                            Task { await app.selectServerInfoNode(endpoint) }
                        }
                    )
                    .frame(minWidth: 300)
                } else {
                    clusterNodeList
                        .frame(width: 280)
                }
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
            if isClusterMode && !app.clusterNodes.isEmpty {
                Toggle(isOn: $showTopology) {
                    Label("Toggle topology view", systemImage: "point.connected.arcs")
                }
                .labelStyle(.iconOnly)
                .toggleStyle(.button)
                .help("Toggle topology view")
            }
        }
        .padding(.horizontal, AppSpacing.large)
        .padding(.vertical, AppSpacing.small)
        .background(AppColor.controlBackground)
    }

    private var clusterNodeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nodes")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppSpacing.medium)
                .padding(.vertical, AppSpacing.small)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    ForEach(app.clusterNodes) { node in
                        Button {
                            Task { await app.selectServerInfoNode(node.endpoint) }
                        } label: {
                            clusterNodeRow(node)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppSpacing.small)
                .padding(.bottom, AppSpacing.small)
            }
        }
        .background(AppColor.controlBackground)
    }

    private var selectedNodeHeader: some View {
        HStack(spacing: AppSpacing.medium) {
            if let node = selectedNode {
                Image(systemName: node.role == .primary ? "server.rack" : "externaldrive.connected.to.line.below")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text(node.endpoint.address)
                        .font(.headline)
                    Text(nodeSubtitle(node))
                        .font(.subheadline)
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
        .padding(.horizontal, AppSpacing.large)
        .padding(.vertical, AppSpacing.medium - AppSpacing.xxSmall)
    }

    private var serverInfoList: some View {
        List {
            capabilitiesSection

            ForEach(sections, id: \.self) { section in
                Section(header: Text(section)) {
                    if let items = app.serverInfo[section] {
                        ForEach(items.keys.sorted(), id: \.self) { key in
                            infoRow(key, items[key] ?? "")
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var capabilitiesSection: some View {
        Section(header: Text("Capabilities")) {
            infoRow("redis", app.serverInfo["Server"]?["redis_version"] ?? "-")
            infoRow("mode", capabilityMode)

            if app.serverCapabilities.isEmpty {
                infoRow("modules", "No modules loaded")
            } else {
                ForEach(app.serverCapabilities) { capability in
                    capabilityRow(capability)
                }
            }
        }
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

    private var capabilityMode: String {
        if isClusterMode || app.serverInfo["Cluster"]?["cluster_enabled"] == "1" {
            return "Cluster"
        }
        return "Standalone"
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(AppFont.monoSubheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 160, alignment: .leading)
            Spacer()
            Text(value)
                .font(AppFont.monoSubheadline)
                .textSelection(.enabled)
        }
    }

    private func capabilityRow(_ capability: RedisServerCapability) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack(alignment: .firstTextBaseline) {
                Text(capability.name)
                    .font(AppFont.monoSubheadline)
                    .foregroundStyle(.primary)
                    .frame(minWidth: 160, alignment: .leading)
                    .textSelection(.enabled)
                Spacer()
                Text(capability.version ?? "-")
                    .font(AppFont.monoSubheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if !capability.details.isEmpty {
                Text(capabilityDetails(capability))
                    .font(AppFont.monoSubheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, AppSpacing.xxSmall)
    }

    private func clusterNodeRow(_ node: RedisClusterNodeSummary) -> some View {
        let isSelected = app.selectedServerInfoNode == node.endpoint

        return HStack(alignment: .top, spacing: AppSpacing.small) {
            Image(systemName: node.role == .primary ? "server.rack" : "externaldrive.connected.to.line.below")
                .frame(width: 16)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(node.endpoint.address)
                    .font(AppFont.monoSubheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(nodeSubtitle(node))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.small)
        .padding(.vertical, AppSpacing.small - AppSpacing.xxSmall)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
    }

    private func summaryItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(AppFont.monoSubheadline)
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

    private func capabilityDetails(_ capability: RedisServerCapability) -> String {
        capability.details.map { "\($0.name)=\($0.value)" }.joined(separator: " · ")
    }
}
