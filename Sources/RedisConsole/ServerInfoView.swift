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
                Button(action: {
                    Task { await app.loadServerInfo() }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding()

            if app.serverInfo.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No server info loaded")
                        .foregroundStyle(.secondary)
                    Button("Load Info") {
                        Task { await app.loadServerInfo() }
                    }
                }
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
