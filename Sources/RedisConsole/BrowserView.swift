import SwiftUI

struct BrowserView: View {
    @EnvironmentObject var app: ConnectionState
    @State private var searchText = ""
    @State private var showingAddKey = false
    @State private var newKeyName = ""
    @State private var newKeyType = "string"
    @State private var newKeyValue = ""

    var body: some View {
        GeometryReader { geo in
            HSplitView {
                // Key List
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Pattern (e.g. user:* or *)", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                app.keyFilter = searchText.isEmpty ? "*" : searchText
                                Task { await app.scanKeys(reset: true) }
                            }
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                app.keyFilter = "*"
                                Task { await app.scanKeys(reset: true) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                        Button {
                            Task { await app.scanKeys(reset: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(app.isLoadingKeys)
                        .help("Refresh")
                    }
                    .padding(8)

                    Divider()

                    if app.isLoadingKeys && app.keys.isEmpty {
                        Spacer()
                        ProgressView("Scanning keys...")
                        Spacer()
                    } else if app.keys.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "key.slash")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text(searchText.isEmpty ? "No keys found" : "No matching keys")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    } else {
                        List(app.keys, selection: $app.selectedKey) { entry in
                            KeyRow(entry: entry)
                                .contextMenu {
                                    Button("View") {
                                        Task { await app.selectKey(entry) }
                                    }
                                    Button("Delete", role: .destructive) {
                                        Task { await app.deleteKey(entry) }
                                    }
                                }
                                .tag(entry)
                        }
                        .listStyle(.plain)
                        .onChange(of: app.selectedKey) { _, newValue in
                            if let key = newValue {
                                Task { await app.selectKey(key) }
                            }
                        }

                        if app.hasMoreKeys {
                            Button("Load more") {
                                Task { await app.scanKeys() }
                            }
                            .padding(8)
                            .disabled(app.isLoadingKeys)
                        }
                    }

                    Divider()

                    HStack {
                        Button {
                            showingAddKey = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help("Add key")

                        Spacer()

                        Text("\(app.keys.count)/\(app.keys.count) keys")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }
                .frame(minWidth: 250, idealWidth: geo.size.width / 2)

                // Key Detail
                KeyDetailView()
                    .frame(minWidth: 250)
            }
        }
        .sheet(isPresented: $showingAddKey) {
            AddKeySheet(
                keyName: $newKeyName,
                keyType: $newKeyType,
                keyValue: $newKeyValue,
                onSave: { name, type, value in
                    Task { await addKey(name: name, type: type, value: value) }
                    showingAddKey = false
                },
                onCancel: { showingAddKey = false }
            )
        }
    }

    private func addKey(name: String, type: String, value: String) async {
        guard let client = app.activeClient else { return }
        switch type {
        case "string":
            let _ = try? await client.send("SET", name, value)
        case "list":
            let _ = try? await client.send("LPUSH", name, value)
        case "hash":
            let parts = value.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let _ = try? await client.send("HSET", name, String(parts[0]), String(parts[1]))
            }
        case "set":
            let _ = try? await client.send("SADD", name, value)
        case "zset":
            let parts = value.split(separator: " ", maxSplits: 1)
            if parts.count == 2 {
                let _ = try? await client.send("ZADD", name, String(parts[0]), String(parts[1]))
            }
        default:
            let _ = try? await client.send("SET", name, value)
        }
        await app.scanKeys(reset: true)
    }
}

struct KeyRow: View {
    let entry: RedisKeyEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.icon)
                .frame(width: 16)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.key)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    if !entry.type.isEmpty {
                        Text(entry.type)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    if let size = entry.size {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .memory))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if entry.ttl != nil {
                        Text(entry.ttlText)
                            .font(.caption2)
                            .foregroundStyle(Color.orange)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct KeyDetailView: View {
    @EnvironmentObject var app: ConnectionState

    var body: some View {
        VStack(spacing: 0) {
            if let key = app.selectedKey {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(key.key)
                            .font(.system(.title3, design: .monospaced))
                            .lineLimit(1)
                        HStack(spacing: 12) {
                            Label(key.type, systemImage: key.icon)
                                .foregroundStyle(.secondary)
                            if let size = key.size {
                                Label(
                                    ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .memory),
                                    systemImage: "doc"
                                )
                                .foregroundStyle(.secondary)
                            }
                            Label(key.ttlText, systemImage: "clock")
                                .foregroundStyle(key.ttl == nil ? Color.secondary : Color.orange)
                        }
                        .font(.caption)
                    }
                    Spacer()
                    Button {
                        Task {
                            let _ = try? await app.activeClient?.send("EXPIRE", key.key, "3600")
                            await app.selectKey(key)
                        }
                    } label: {
                        Image(systemName: "clock.badge.plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Set 1h TTL")

                    Button(role: .destructive) {
                        Task { await app.deleteKey(key) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete key")
                }
                .padding()

                Divider()

                if app.isLoadingDetail {
                    Spacer()
                    ProgressView("Loading value...")
                    Spacer()
                } else if !app.keyDetailRows.isEmpty {
                    List {
                        Section {
                            ForEach(Array(app.keyDetailRows.enumerated()), id: \.offset) { _, row in
                                HStack(alignment: .top) {
                                    Text(row.0)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 100, alignment: .leading)
                                    Text(row.1)
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                        } header: {
                            HStack {
                                Text(app.keyType == "zset" ? "Score" : "Key")
                                    .frame(width: 100, alignment: .leading)
                                Text("Value")
                                Spacer()
                            }
                            .font(.caption)
                        }
                    }
                    .listStyle(.inset)
                } else {
                    ScrollView {
                        Text(app.keyDetail)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Select a key to view its value")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}

struct AddKeySheet: View {
    @Binding var keyName: String
    @Binding var keyType: String
    @Binding var keyValue: String
    let onSave: (String, String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add New Key")
                .font(.headline)

            Form {
                TextField("Key name", text: $keyName)
                Picker("Type", selection: $keyType) {
                    Text("String").tag("string")
                    Text("List").tag("list")
                    Text("Hash").tag("hash")
                    Text("Set").tag("set")
                    Text("Sorted Set").tag("zset")
                }
                TextField("Value", text: $keyValue, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Add") { onSave(keyName, keyType, keyValue) }
                    .disabled(keyName.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
