import SwiftUI

struct ServerInfoView: View {
    @EnvironmentObject var app: ConnectionState

    var sections: [String] {
        app.serverInfo.keys.sorted()
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

            if app.serverInfo.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "info.circle",
                    title: "No server info loaded",
                    actionTitle: "Load Info",
                    action: { Task { await app.loadServerInfo() } }
                )
                Spacer()
            } else {
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
        }
    }
}
