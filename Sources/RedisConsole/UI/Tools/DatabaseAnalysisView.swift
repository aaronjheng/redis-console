import SwiftUI

// MARK: - Database Analysis View

struct DatabaseAnalysisView: View {
    @Environment(ConnectionState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Database Analysis")
                    .font(.headline)
                Spacer()
                if app.isLoadingAnalysis {
                    ProgressView()
                        .scaleEffect(0.7)
                        .controlSize(.small)
                }
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await app.runDatabaseAnalysis() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(app.isLoadingAnalysis)
                .help("Refresh")

                Button("Export", systemImage: "square.and.arrow.up") {
                    exportAnalysis()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(app.analysis == nil)
                .help("Export")
            }
            .padding(AppSpacing.large)

            Divider()

            if let error = app.analysisError {
                ErrorBanner(message: error)
                Divider()
            }

            if app.isLoadingAnalysis {
                Spacer()
                LoadingState(message: "Analyzing database...")
                Spacer()
            } else if let analysis = app.analysis {
                analysisContent(analysis)
            } else {
                Spacer()
                ContentUnavailableView(
                    "No analysis data",
                    systemImage: "chart.pie",
                    description: Text("Run analysis to see database statistics")
                )
                Button("Run Analysis") {
                    Task { await app.runDatabaseAnalysis() }
                }
                .padding(.top, 8)
                Spacer()
            }
            Divider()
            WorkspaceFooterBar {
                if let analysis = app.analysis {
                    StatusFooterView(
                        countText: "\(analysis.totalKeys) keys",
                        sizeText: analysis.serverMetrics.usedMemoryHuman
                    )
                } else if app.isLoadingAnalysis {
                    Label("Analyzing…", systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                } else if app.analysisError != nil {
                    Label("Analysis failed", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(AppColor.error)
                } else {
                    Text("No analysis data")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .onDisappear {
            app.cancelAnalysis()
        }
    }

    @ViewBuilder
    private func analysisContent(_ analysis: DatabaseAnalysis) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Summary bar
                summaryBar(analysis)
                Divider()

                VStack(spacing: AppSpacing.small) {
                    // Type Distribution
                    typeDistributionSection(analysis)
                    // Top Keys
                    topKeysSection(analysis)
                }
                .padding([.horizontal, .top], AppSpacing.large)

                // Expiration Timeline
                expirationSection(analysis)
                    .padding(.horizontal, AppSpacing.large)
                    .padding(.bottom, AppSpacing.small)
            }
        }
    }

    private func summaryBar(_ analysis: DatabaseAnalysis) -> some View {
        HStack(spacing: AppSpacing.large) {
            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text("Last analyzed:")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                HStack(spacing: 0) {
                    Text(analysis.analyzedAt, style: .time)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(" (\(analysis.keysSampled) keys)")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }

            Divider().frame(height: 30)

            StatItem(label: "Total Keys", value: "\(analysis.totalKeys)")
            StatItem(label: "Total Memory", value: analysis.serverMetrics.usedMemoryHuman)
            StatItem(label: "Hit Rate", value: String(format: "%.1f%%", analysis.serverMetrics.hitRate))
            StatItem(label: "Ops/sec", value: "\(analysis.serverMetrics.opsPerSecond)")
            StatItem(label: "Clients", value: "\(analysis.serverMetrics.connectedClients)")

            if analysis.isEstimate {
                Badge(
                    text: "Estimate",
                    foregroundColor: AppColor.warning,
                    backgroundColor: AppColor.warning.opacity(0.12)
                )
            }
        }
        .padding(.horizontal, AppSpacing.large)
        .padding(.vertical, AppSpacing.small)
    }

    private func typeDistributionSection(_ analysis: DatabaseAnalysis) -> some View {
        Card(title: "Type Distribution") {
            let types = analysis.typeDistribution.keys.sorted()
            if types.isEmpty {
                Text("No data")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: AppSpacing.xSmall) {
                    HStack {
                        Text("Type").font(.body).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                        Text("Count").font(.body).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
                        Text("Memory").font(.body).foregroundStyle(.secondary).frame(width: 120, alignment: .trailing)
                        Text("Avg").font(.body).foregroundStyle(.secondary).frame(width: 100, alignment: .trailing)
                    }
                    ForEach(types, id: \.self) { type in
                        if let stats = analysis.typeDistribution[type] {
                            HStack {
                                Text(type.capitalized)
                                    .font(.body)
                                    .frame(width: 60, alignment: .leading)
                                Text("\(stats.count)")
                                    .font(AppFont.dataCell)
                                    .frame(width: 70, alignment: .trailing)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(stats.memory), countStyle: .file))
                                    .font(AppFont.dataCell)
                                    .frame(width: 120, alignment: .trailing)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(stats.avgSize), countStyle: .file))
                                    .font(AppFont.dataCell)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 100, alignment: .trailing)
                            }
                        }
                    }
                }
                .padding(AppSpacing.small)
                .background(AppColor.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
            }
        }
    }

    private func topKeysSection(_ analysis: DatabaseAnalysis) -> some View {
        Card(title: "Top Keys by Memory") {
            if analysis.topKeysByMemory.isEmpty {
                Text("No data")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Grid(horizontalSpacing: AppSpacing.small, verticalSpacing: AppSpacing.xxSmall) {
                    ForEach(analysis.topKeysByMemory.prefix(10)) { entry in
                        GridRow {
                            Text(entry.key)
                                .font(.body)
                                .lineLimit(1)
                                .gridColumnAlignment(.leading)
                            Text(entry.memoryText)
                                .font(AppFont.dataCell)
                                .foregroundStyle(.secondary)
                                .frame(width: AppSize.formFieldWidth, alignment: .trailing)
                        }
                    }
                }
                .padding(AppSpacing.small)
                .background(AppColor.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
            }
        }
    }

    private func expirationSection(_ analysis: DatabaseAnalysis) -> some View {
        Card(title: "Expiration Timeline") {
            if analysis.expirationSummary.isEmpty {
                Text("No data")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                let maxCount = analysis.expirationSummary.map(\.keyCount).max() ?? 1
                VStack(spacing: AppSpacing.small - AppSpacing.xxSmall) {
                    ForEach(analysis.expirationSummary) { bucket in
                        HStack(spacing: AppSpacing.small) {
                            Text(bucket.label)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .leading)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: AppRadius.small)
                                        .fill(.quaternary)
                                        .frame(height: 16)
                                    RoundedRectangle(cornerRadius: AppRadius.small)
                                        .fill(expirationColor(bucket.label))
                                        .frame(width: max(4, geo.size.width * CGFloat(bucket.keyCount) / CGFloat(maxCount)), height: 16)
                                }
                            }
                            .frame(height: 16)

                            Text("\(bucket.keyCount)")
                                .font(AppFont.dataCell)
                                .frame(width: 50, alignment: .trailing)
                            Text(bucket.memoryText)
                                .font(AppFont.dataCell)
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .trailing)
                        }
                    }
                }
                .padding(AppSpacing.small)
                .background(AppColor.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
            }
        }
    }

    private func typeIcon(_ type: String) -> String {
        switch type.lowercased() {
        case "string": return "doc.text"
        case "list": return "list.bullet"
        case "hash": return "tablecells"
        case "set": return "circle.grid.cross"
        case "zset": return "arrow.up.arrow.down.circle"
        default: return "questionmark.circle"
        }
    }

    private func typeColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "string": return AppColor.chartString
        case "list": return AppColor.chartList
        case "hash": return AppColor.chartHash
        case "set": return AppColor.chartSet
        case "zset": return AppColor.chartZSet
        case "stream": return .secondary
        default: return .secondary
        }
    }

    private func expirationColor(_ label: String) -> Color {
        switch label {
        case "< 1h": return AppColor.ttlExpired
        case "1-6h": return AppColor.ttlShort
        case "6-24h": return AppColor.ttlMedium
        case "1-7d": return AppColor.ttlLong
        case "7-30d": return AppColor.ttlDistant
        case "> 30d": return .secondary
        case "No expiry": return .gray
        default: return .secondary
        }
    }

    private func exportAnalysis() {
        guard let analysis = app.analysis else { return }
        var lines: [String] = [
            "Database Analysis - \(DateFormatter.localizedString(from: analysis.analyzedAt, dateStyle: .medium, timeStyle: .medium))",
            "Keys Sampled: \(analysis.keysSampled)\(analysis.isEstimate ? " (estimate)" : "")",
            "Total Keys: \(analysis.totalKeys)",
            "Total Memory: \(analysis.serverMetrics.usedMemoryHuman)",
            "Hit Rate: \(String(format: "%.1f%%", analysis.serverMetrics.hitRate))",
            "Ops/sec: \(analysis.serverMetrics.opsPerSecond)",
            "Clients: \(analysis.serverMetrics.connectedClients)",
            "",
            "Type Distribution:",
        ]
        for (type, stats) in analysis.typeDistribution.sorted(by: { $0.value.count > $1.value.count }) {
            let memStr = ByteCountFormatter.string(fromByteCount: Int64(stats.memory), countStyle: .file)
            lines.append("  \(type): \(stats.count) keys, \(memStr)")
        }
        lines.append("")
        lines.append("Top Keys by Memory:")
        for entry in analysis.topKeysByMemory.prefix(20) {
            lines.append("  \(entry.key) (\(entry.type)) - \(entry.memoryText)")
        }
        lines.append("")
        lines.append("Expiration Timeline:")
        for bucket in analysis.expirationSummary {
            lines.append("  \(bucket.label): \(bucket.keyCount) keys, \(bucket.memoryText)")
        }

        let text = lines.joined(separator: "\n")
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "analysis-\(ISO8601DateFormatter().string(from: analysis.analyzedAt)).txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.body)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(AppFont.dataCell)
                .foregroundStyle(.primary)
        }
    }
}
