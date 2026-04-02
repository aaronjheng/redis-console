import SwiftUI

struct SlowLogView: View {
    @EnvironmentObject var app: ConnectionState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Slow Log")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await app.loadSlowLog() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding()

            if app.slowLogEntries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No slow log entries")
                        .foregroundStyle(.secondary)
                    Text("Slow operations will appear here")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Button("Load Slow Log") {
                        Task { await app.loadSlowLog() }
                    }
                }
                Spacer()
            } else {
                Table(app.slowLogEntries) {
                    TableColumn("#") { entry in
                        Text("\(entry.index)")
                            .font(.system(.caption, design: .monospaced))
                    }
                    .width(50)

                    TableColumn("Timestamp") { entry in
                        Text(entry.timestamp, style: .time)
                            .font(.caption)
                    }
                    .width(80)

                    TableColumn("Duration") { entry in
                        Text(entry.durationText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(entry.durationMicroseconds > 100_000 ? .red : .primary)
                    }
                    .width(80)

                    TableColumn("Command") { entry in
                        Text(entry.command.joined(separator: " "))
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }

                    TableColumn("Client") { entry in
                        Text(entry.clientAddress)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .width(120)
                }
            }
        }
    }
}
