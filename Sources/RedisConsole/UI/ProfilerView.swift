import AppKit
import SwiftUI

struct ProfilerView: View {
    @Environment(ConnectionState.self) private var app
    @State private var filterText = ""
    @State private var autoScroll = true
    @State private var hideNoiseCommands = true
    @State private var selectedEntryID: RedisProfilerEntry.ID?
    @State private var showStats = false

    private var filteredEntries: [RedisProfilerEntry] {
        let visibleEntries =
            hideNoiseCommands
            ? app.profilerEntries.filter { !$0.isNoiseCommand }
            : app.profilerEntries

        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return visibleEntries }

        return visibleEntries.filter { entry in
            entry.searchText.contains(query)
        }
    }

    private var selectedEntry: RedisProfilerEntry? {
        guard let selectedEntryID else { return nil }
        return filteredEntries.first { $0.id == selectedEntryID }
    }

    private var lastVisibleEntryID: RedisProfilerEntry.ID? {
        filteredEntries.last?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            ProfilerToolbarView(
                filterText: $filterText,
                autoScroll: $autoScroll,
                hideNoiseCommands: $hideNoiseCommands,
                showStats: $showStats,
                isStarting: app.isProfilerStarting,
                isRunning: app.isProfilerRunning,
                onToggleCapture: toggleCapture,
                onClear: clearProfiler
            )

            if let error = app.profilerError {
                ProfilerErrorBanner(message: error)
            }

            if showStats {
                ProfilerStatsView(entries: filteredEntries)
            } else {
                ProfilerContentView(
                    entries: filteredEntries,
                    isStarting: app.isProfilerStarting,
                    isRunning: app.isProfilerRunning,
                    selectedEntryID: $selectedEntryID,
                    autoScroll: autoScroll,
                    lastVisibleEntryID: lastVisibleEntryID,
                    onStart: app.startProfiler
                )
            }

            Divider()

            ProfilerFooterView(
                filteredCount: filteredEntries.count,
                retainedCount: app.profilerEntries.count,
                capturedCount: app.profilerCapturedCount,
                selectedEntry: selectedEntry
            )
        }
    }

    private func toggleCapture() {
        if app.isProfilerRunning || app.isProfilerStarting {
            app.stopProfiler()
        } else {
            app.startProfiler()
        }
    }

    private func clearProfiler() {
        selectedEntryID = nil
        app.clearProfiler()
    }
}

private struct ProfilerContentView: View {
    let entries: [RedisProfilerEntry]
    let isStarting: Bool
    let isRunning: Bool
    @Binding var selectedEntryID: RedisProfilerEntry.ID?
    let autoScroll: Bool
    let lastVisibleEntryID: RedisProfilerEntry.ID?
    let onStart: () -> Void

    var body: some View {
        if entries.isEmpty {
            ProfilerEmptyStateView(
                isStarting: isStarting,
                isRunning: isRunning,
                onStart: onStart
            )
        } else {
            ProfilerEntriesView(
                entries: entries,
                selectedEntryID: $selectedEntryID,
                autoScroll: autoScroll,
                lastVisibleEntryID: lastVisibleEntryID
            )
        }
    }
}

private struct ProfilerEmptyStateView: View {
    let isStarting: Bool
    let isRunning: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            EmptyStateView(
                icon: isRunning ? "dot.radiowaves.left.and.right" : "waveform.path.ecg",
                title: isRunning ? "Waiting for Redis commands" : "Profiler is stopped",
                subtitle: isRunning ? "Run commands from Shell or another client to see them here." : nil,
                actionTitle: isRunning || isStarting ? nil : "Start Profiler",
                action: isRunning || isStarting ? nil : onStart
            )
            if !isRunning && !isStarting {
                Spacer().frame(height: 16)
                Label("MONITOR can slow busy servers", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct ProfilerToolbarView: View {
    @Binding var filterText: String
    @Binding var autoScroll: Bool
    @Binding var hideNoiseCommands: Bool
    @Binding var showStats: Bool
    let isStarting: Bool
    let isRunning: Bool
    let onToggleCapture: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Profiler")
                    .font(.headline)

                ProfilerStatusPill(isStarting: isStarting, isRunning: isRunning)

                Spacer()

                Button(action: onClear) {
                    Label("Clear", systemImage: "trash")
                }

                Button(action: onToggleCapture) {
                    Label(captureButtonTitle, systemImage: captureButtonIcon)
                }
                .buttonStyle(.borderedProminent)

                Toggle(isOn: $showStats) {
                    Label("Toggle statistics view", systemImage: "chart.bar")
                }
                .labelStyle(.iconOnly)
                .toggleStyle(.button)
                .help("Toggle statistics view")
            }
            .padding()

            Divider()

            HStack(spacing: 10) {
                ZStack(alignment: .trailing) {
                    TextField("Filter command, node, source, database, or raw text", text: $filterText)
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

                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.switch)

                Toggle("Hide noise", isOn: $hideNoiseCommands)
                    .toggleStyle(.switch)

                Color.clear.frame(width: 0, height: 0)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()
        }
        .background(.bar)
    }

    private var captureButtonTitle: String {
        if isStarting { return "Stop" }
        return isRunning ? "Stop" : "Start"
    }

    private var captureButtonIcon: String {
        if isStarting { return "stop.fill" }
        return isRunning ? "stop.fill" : "play.fill"
    }
}

private struct ProfilerStatusPill: View {
    let isStarting: Bool
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
    }

    private var statusText: String {
        if isStarting { return "Starting" }
        return isRunning ? "Running" : "Stopped"
    }

    private var indicatorColor: Color {
        if isStarting { return .orange }
        return isRunning ? .green : .secondary
    }
}

private struct ProfilerErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }
}

private struct ProfilerEntriesView: View {
    let entries: [RedisProfilerEntry]
    @Binding var selectedEntryID: RedisProfilerEntry.ID?
    let autoScroll: Bool
    let lastVisibleEntryID: RedisProfilerEntry.ID?

    var body: some View {
        VStack(spacing: 0) {
            ProfilerHeaderRow()
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            ProfilerEntryRow(
                                entry: entry,
                                isSelected: selectedEntryID == entry.id,
                                onSelect: { selectedEntryID = entry.id }
                            )
                            .id(entry.id)
                        }
                    }
                }
                .onChange(of: lastVisibleEntryID) { _, newValue in
                    guard autoScroll, let newValue else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newValue, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct ProfilerHeaderRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("Time")
                .frame(width: 100, alignment: .leading)
            Text("DB")
                .frame(width: 44, alignment: .leading)
            Text("Node")
                .frame(width: 170, alignment: .leading)
            Text("Source")
                .frame(width: 170, alignment: .leading)
            Text("Command")
                .frame(width: 110, alignment: .leading)
            Text("Arguments")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct ProfilerEntryRow: View {
    let entry: RedisProfilerEntry
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Text(entry.timeText)
                    .frame(width: 100, alignment: .leading)
                    .foregroundStyle(.secondary)
                Text(entry.databaseText)
                    .frame(width: 44, alignment: .leading)
                    .foregroundStyle(.secondary)
                Text(entry.nodeText)
                    .frame(width: 170, alignment: .leading)
                    .foregroundStyle(.secondary)
                    .truncationMode(.middle)
                Text(entry.source)
                    .frame(width: 170, alignment: .leading)
                    .truncationMode(.middle)
                Text(entry.commandName)
                    .frame(width: 110, alignment: .leading)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
                Text(entry.argumentsText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .truncationMode(.middle)
            }
            .font(.system(.caption, design: .monospaced))
            .lineLimit(1)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy Raw Line") {
                copyToPasteboard(entry.rawLine)
            }
            Button("Copy Command") {
                copyToPasteboard(entry.commandText)
            }
        }
    }

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}

private struct ProfilerFooterView: View {
    let filteredCount: Int
    let retainedCount: Int
    let capturedCount: Int
    let selectedEntry: RedisProfilerEntry?

    var body: some View {
        VStack(spacing: 0) {
            if let selectedEntry {
                HStack(alignment: .top, spacing: 8) {
                    Text("Raw")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .leading)
                    Text(selectedEntry.rawLine)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(3)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()
            }

            WorkspaceFooterBar {
                StatusFooterView(
                    countText: "Showing \(filteredCount) of \(retainedCount)",
                    sizeText: "Captured \(capturedCount)"
                )
                Spacer()
            }
        }
    }
}
