import SwiftUI

// MARK: - Profiler Statistics View

struct ProfilerStatsView: View {
    let entries: [RedisProfilerEntry]

    private var stats: ProfilerStats {
        ProfilerStats.compute(from: entries)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                topCommandsSection
                Divider()
                commandTypeSection
                Divider()
                databaseSection
                Divider()
                sourceSection
            }
            .padding()
        }
    }

    private var topCommandsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top 10 Commands")
                .font(.headline)

            ForEach(Array(stats.commandFrequency.enumerated()), id: \.offset) { index, item in
                let maxCount = stats.commandFrequency.first?.count ?? 1
                HStack(spacing: 8) {
                    Text("\(index + 1).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    Text(item.command)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 100, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: geometry.size.width, height: 16)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor)
                                .frame(
                                    width: CGFloat(item.count) / CGFloat(maxCount) * geometry.size.width,
                                    height: 16
                                )
                        }
                    }
                    .frame(height: 16)
                    Text("\(item.count)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
    }

    private var commandTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By Command Type")
                .font(.headline)

            ForEach(stats.commandTypeDistribution, id: \.type) { item in
                let maxCount = stats.commandTypeDistribution.first?.count ?? 1
                HStack(spacing: 8) {
                    Text(item.type)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 80, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(typeColor(item.type).opacity(0.15))
                                .frame(width: geometry.size.width, height: 16)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(typeColor(item.type))
                                .frame(
                                    width: CGFloat(item.count) / CGFloat(maxCount) * geometry.size.width,
                                    height: 16
                                )
                        }
                    }
                    .frame(height: 16)
                    Text("\(item.count)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
    }

    private var databaseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By Database")
                .font(.headline)

            ForEach(stats.databaseDistribution, id: \.database) { item in
                let maxCount = stats.databaseDistribution.first?.count ?? 1
                HStack(spacing: 8) {
                    Text("DB \(item.database)")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 80, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: geometry.size.width, height: 16)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.orange)
                                .frame(
                                    width: CGFloat(item.count) / CGFloat(maxCount) * geometry.size.width,
                                    height: 16
                                )
                        }
                    }
                    .frame(height: 16)
                    Text("\(item.count)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top 10 Sources")
                .font(.headline)

            ForEach(Array(stats.sourceDistribution.enumerated()), id: \.offset) { index, item in
                let maxCount = stats.sourceDistribution.first?.count ?? 1
                HStack(spacing: 8) {
                    Text("\(index + 1).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    Text(item.source)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 160, alignment: .leading)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.purple.opacity(0.15))
                                .frame(width: geometry.size.width, height: 16)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.purple)
                                .frame(
                                    width: CGFloat(item.count) / CGFloat(maxCount) * geometry.size.width,
                                    height: 16
                                )
                        }
                    }
                    .frame(height: 16)
                    Text("\(item.count)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "Read": return .blue
        case "Write": return .orange
        case "Admin": return .red
        default: return .gray
        }
    }
}
