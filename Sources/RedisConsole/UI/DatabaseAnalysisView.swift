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
                Button {
                    Task { await app.runDatabaseAnalysis() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(app.isLoadingAnalysis)
                .help("Refresh")

                Button {
                    exportAnalysis()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(app.analysis == nil)
                .help("Export")
            }
            .padding()

            if let error = app.analysisError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                Divider()
            }

            if app.isLoadingAnalysis {
                Spacer()
                ProgressView("Analyzing database...")
                Spacer()
            } else if let analysis = app.analysis {
                analysisContent(analysis)
            } else {
                Spacer()
                EmptyStateView(
                    icon: "chart.pie",
                    title: "No analysis data",
                    subtitle: "Run analysis to see database statistics",
                    actionTitle: "Run Analysis",
                    action: { Task { await app.runDatabaseAnalysis() } }
                )
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

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    // Type Distribution
                    typeDistributionSection(analysis)
                    // Top Keys
                    topKeysSection(analysis)
                }
                .padding()

                // Expiration Timeline
                expirationSection(analysis)
                    .padding(.horizontal)
                    .padding(.bottom)
            }
        }
    }

    private func summaryBar(_ analysis: DatabaseAnalysis) -> some View {
        HStack(spacing: AppTheme.spacingLarge) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Last analyzed:")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(analysis.analyzedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                + Text(" (\(analysis.keysSampled) keys)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider().frame(height: 30)

            StatItem(label: "Total Keys", value: "\(analysis.totalKeys)")
            StatItem(label: "Total Memory", value: analysis.serverMetrics.usedMemoryHuman)
            StatItem(label: "Hit Rate", value: String(format: "%.1f%%", analysis.serverMetrics.hitRate))
            StatItem(label: "Ops/sec", value: "\(analysis.serverMetrics.opsPerSecond)")
            StatItem(label: "Clients", value: "\(analysis.serverMetrics.connectedClients)")

            if analysis.isEstimate {
                Text("Estimate")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func typeDistributionSection(_ analysis: DatabaseAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type Distribution")
                .font(.subheadline)
                .bold()

            let types = analysis.typeDistribution.keys.sorted()
            if types.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    HStack {
                        Text("Type").font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                        Text("Count").font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
                        Text("Memory").font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                        Text("Avg").font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
                    }
                    ForEach(types, id: \.self) { type in
                        if let stats = analysis.typeDistribution[type] {
                            HStack {
                                HStack(spacing: 4) {
                                    Image(systemName: typeIcon(type))
                                        .foregroundStyle(typeColor(type))
                                    Text(type.capitalized)
                                        .font(.caption)
                                }
                                .frame(width: 60, alignment: .leading)
                                Text("\(stats.count)")
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 60, alignment: .trailing)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(stats.memory), countStyle: .file))
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 80, alignment: .trailing)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(stats.avgSize), countStyle: .file))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .trailing)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .background(.bar)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func topKeysSection(_ analysis: DatabaseAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Keys by Memory")
                .font(.subheadline)
                .bold()

            if analysis.topKeysByMemory.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 2) {
                    ForEach(analysis.topKeysByMemory.prefix(10)) { entry in
                        HStack(spacing: 4) {
                            Image(systemName: typeIcon(entry.type))
                                .foregroundStyle(typeColor(entry.type))
                                .font(.caption2)
                            Text(entry.key)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(entry.memoryText)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .background(.bar)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func expirationSection(_ analysis: DatabaseAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Expiration Timeline")
                .font(.subheadline)
                .bold()

            if analysis.expirationSummary.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let maxCount = analysis.expirationSummary.map(\.keyCount).max() ?? 1
                VStack(spacing: 6) {
                    ForEach(analysis.expirationSummary) { bucket in
                        HStack(spacing: 8) {
                            Text(bucket.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .leading)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(.quaternary)
                                        .frame(height: 16)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(expirationColor(bucket.label))
                                        .frame(width: max(4, geo.size.width * CGFloat(bucket.keyCount) / CGFloat(maxCount)), height: 16)
                                }
                            }
                            .frame(height: 16)

                            Text("\(bucket.keyCount)")
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 50, alignment: .trailing)
                            Text(bucket.memoryText)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .trailing)
                        }
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .background(.bar)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        case "string": return .blue
        case "list": return .green
        case "hash": return .orange
        case "set": return .purple
        case "zset": return .pink
        default: return .secondary
        }
    }

    private func expirationColor(_ label: String) -> Color {
        switch label {
        case "< 1h": return .red
        case "1-6h": return .orange
        case "6-24h": return .yellow
        case "1-7d": return .blue
        case "7-30d": return .green
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
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}
