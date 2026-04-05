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
            _ = try? await client.send("SET", name, value)
        case "list":
            _ = try? await client.send("LPUSH", name, value)
        case "hash":
            let parts = value.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                _ = try? await client.send("HSET", name, String(parts[0]), String(parts[1]))
            }
        case "set":
            _ = try? await client.send("SADD", name, value)
        case "zset":
            let parts = value.split(separator: " ", maxSplits: 1)
            if parts.count == 2 {
                _ = try? await client.send("ZADD", name, String(parts[0]), String(parts[1]))
            }
        default:
            _ = try? await client.send("SET", name, value)
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
    @State private var editingString = false
    @State private var stringValue = ""
    @State private var showingAddHashField = false
    @State private var newHashField = ""
    @State private var newHashValue = ""
    @State private var editingHashField: String?
    @State private var editingHashValue = ""
    @State private var showingAddListElement = false
    @State private var newListElement = ""
    @State private var newListPosition: ListPosition = .head
    @State private var editingListElement: ListElementEdit?
    @State private var showingAddSetMember = false
    @State private var newSetMember = ""
    @State private var showingAddZSetMember = false
    @State private var newZSetMember = ""
    @State private var newZSetScore = ""
    @State private var editingZSetMember: ZSetMemberEdit?


    enum ListPosition {
        case head, tail
    }

    var body: some View {
        VStack(spacing: 0) {
            if let key = app.selectedKey {
                headerView(key: key)

                Divider()

                if app.isLoadingDetail {
                    Spacer()
                    ProgressView("Loading value...")
                    Spacer()
                } else if !app.keyDetailRows.isEmpty {
                    switch app.keyType {
                    case "hash":
                        HashDetailView(
                            key: key.key,
                            rows: app.keyDetailRows,
                            valueSize: app.valueSize,
                            onAddField: { showingAddHashField = true },
                            onEditField: { field, value in
                                editingHashField = field
                                editingHashValue = value
                            },
                            onDeleteField: { field in
                                Task {
                                    await app.deleteHashField(key: key.key, field: field)
                                    await app.refreshSelectedKey()
                                }
                            }
                        )
                        .sheet(isPresented: $showingAddHashField) {
                            AddHashFieldSheet(
                                key: key.key,
                                field: $newHashField,
                                value: $newHashValue,
                                onSave: { field, value in
                                    Task {
                                        await app.addHashField(key: key.key, field: field, value: value)
                                        await app.refreshSelectedKey()
                                    }
                                    showingAddHashField = false
                                },
                                onCancel: { showingAddHashField = false }
                            )
                        }
                        .sheet(
                            item: $editingHashField,
                            onDismiss: {
                                editingHashField = nil
                            }
                        ) { field in
                            EditHashFieldSheet(
                                key: key.key,
                                field: field,
                                value: $editingHashValue,
                                onSave: { field, value in
                                    Task {
                                        await app.updateHashField(key: key.key, field: field, value: value)
                                        await app.refreshSelectedKey()
                                    }
                                    editingHashField = nil
                                },
                                onCancel: { editingHashField = nil }
                            )
                        }

                    case "list":
                        ListDetailView(
                            key: key.key,
                            rows: app.keyDetailRows,
                            valueSize: app.valueSize,
                            onAddElement: { showingAddListElement = true },
                            onEditElement: { index, value in
                                editingListElement = ListElementEdit(index: index, value: value)
                            },
                            onDeleteElement: { _, value in
                                Task {
                                    await app.deleteListElement(key: key.key, value: value)
                                    await app.refreshSelectedKey()
                                }
                            }
                        )
                        .sheet(isPresented: $showingAddListElement) {
                            AddListElementSheet(
                                key: key.key,
                                value: $newListElement,
                                position: $newListPosition,
                                onSave: { value, position in
                                    Task {
                                        await app.addListElement(key: key.key, value: value, tail: position == .tail)
                                        await app.refreshSelectedKey()
                                    }
                                    showingAddListElement = false
                                },
                                onCancel: { showingAddListElement = false }
                            )
                        }
                        .sheet(
                            item: $editingListElement,
                            onDismiss: {
                                editingListElement = nil
                            }
                        ) { element in
                            EditListElementSheet(
                                key: key.key,
                                index: element.index,
                                value: element.value,
                                onSave: { index, value in
                                    Task {
                                        await app.updateListElement(key: key.key, index: index, value: value)
                                        await app.refreshSelectedKey()
                                    }
                                    editingListElement = nil
                                },
                                onCancel: { editingListElement = nil }
                            )
                        }

                    case "set":
                        SetDetailView(
                            key: key.key,
                            rows: app.keyDetailRows,
                            valueSize: app.valueSize,
                            onAddMember: { showingAddSetMember = true },
                            onDeleteMember: { member in
                                Task {
                                    await app.deleteSetMember(key: key.key, member: member)
                                    await app.refreshSelectedKey()
                                }
                            }
                        )
                        .sheet(isPresented: $showingAddSetMember) {
                            AddSetMemberSheet(
                                key: key.key,
                                member: $newSetMember,
                                onSave: { member in
                                    Task {
                                        await app.addSetMember(key: key.key, member: member)
                                        await app.refreshSelectedKey()
                                    }
                                    showingAddSetMember = false
                                },
                                onCancel: { showingAddSetMember = false }
                            )
                        }

                    case "zset":
                        ZSetDetailView(
                            key: key.key,
                            rows: app.keyDetailRows,
                            valueSize: app.valueSize,
                            onAddMember: { showingAddZSetMember = true },
                            onEditMember: { member, score in
                                editingZSetMember = ZSetMemberEdit(member: member, score: score)
                            },
                            onDeleteMember: { member in
                                Task {
                                    await app.deleteZSetMember(key: key.key, member: member)
                                    await app.refreshSelectedKey()
                                }
                            }
                        )
                        .sheet(isPresented: $showingAddZSetMember) {
                            AddZSetMemberSheet(
                                key: key.key,
                                member: $newZSetMember,
                                score: $newZSetScore,
                                onSave: { member, score in
                                    Task {
                                        await app.addZSetMember(key: key.key, member: member, score: score)
                                        await app.refreshSelectedKey()
                                    }
                                    showingAddZSetMember = false
                                },
                                onCancel: { showingAddZSetMember = false }
                            )
                        }
                        .sheet(
                            item: $editingZSetMember,
                            onDismiss: {
                                editingZSetMember = nil
                            }
                        ) { zsetEntry in
                            EditZSetMemberSheet(
                                key: key.key,
                                member: zsetEntry.member,
                                score: zsetEntry.score,
                                onSave: { member, score in
                                    Task {
                                        await app.updateZSetScore(key: key.key, member: member, score: score)
                                        await app.refreshSelectedKey()
                                    }
                                    editingZSetMember = nil
                                },
                                onCancel: { editingZSetMember = nil }
                            )
                        }

                    default:
                        genericRowsView
                    }
                } else {
                    switch app.keyType {
                    case "string":
                        StringDetailView(
                            key: key.key,
                            value: app.keyDetail,
                            valueSize: app.valueSize,
                            onSave: { value in
                                Task {
                                    await app.updateStringValue(key: key.key, value: value)
                                    await app.refreshSelectedKey()
                                }
                            }
                        )
                    default:
                        emptyValueView
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

    private func headerView(key: RedisKeyEntry) -> some View {
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
                Task { await app.refreshSelectedKey() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")

            Button {
                Task {
                    _ = try? await app.activeClient?.send("EXPIRE", key.key, "3600")
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
    }

    private var genericRowsView: some View {
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
    }

    private var emptyValueView: some View {
        ScrollView {
            Text(app.keyDetail)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }
}

// MARK: - String Detail View

struct StringDetailView: View {
    let key: String
    let value: String
    let valueSize: Int?
    let onSave: (String) -> Void

    @State private var isEditing = false
    @State private var editValue = ""

    var body: some View {
        VStack(spacing: 0) {
            if isEditing {
                VStack(spacing: 12) {
                    HStack {
                        Text("Edit Value")
                            .font(.headline)
                        Spacer()
                        HStack(spacing: 8) {
                            Button("Cancel") {
                                isEditing = false
                            }
                            .buttonStyle(.borderless)
                            Button("Save") {
                                onSave(editValue)
                                isEditing = false
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    TextEditor(text: $editValue)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.horizontal)
                        .padding(.bottom)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(value)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .overlay(alignment: .topTrailing) {
                    Button {
                        editValue = value
                        isEditing = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .padding()
                    .help("Edit value")
                }
            }

            Divider()

            HStack {
                Spacer()

                if let valueSize {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(valueSize), countStyle: .memory))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }
}

// MARK: - Hash Detail View

struct HashRow: Identifiable {
    let id = UUID()
    let field: String
    let value: String
}

struct HashDetailView: View {
    let key: String
    let rows: [(String, String)]
    let valueSize: Int?
    let onAddField: () -> Void
    let onEditField: (String, String) -> Void
    let onDeleteField: (String) -> Void

    private var hashRows: [HashRow] {
        rows.map { HashRow(field: $0.0, value: $0.1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(hashRows) {
                TableColumn("Field") { row in
                    Text(row.field)
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 100, ideal: 150, max: 300)

                TableColumn("Value") { row in
                    Text(row.value)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                }

                TableColumn("Actions") { row in
                    HStack(spacing: 8) {
                        Button {
                            onEditField(row.field, row.value)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Edit field")

                        Button {
                            onDeleteField(row.field)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .help("Delete field")
                    }
                }
                .width(80)
            }

            Divider()

            HStack {
                Button {
                    onAddField()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add field")

                Spacer()

                HStack(spacing: 4) {
                    Text("\(rows.count) fields")
                    if let valueSize {
                        Text("\u{00B7}")
                        Text(ByteCountFormatter.string(fromByteCount: Int64(valueSize), countStyle: .memory))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }
}

// MARK: - List Detail View

struct ListRow: Identifiable {
    let id = UUID()
    let index: Int
    let value: String
}

struct ListDetailView: View {
    let key: String
    let rows: [(String, String)]
    let valueSize: Int?
    let onAddElement: () -> Void
    let onEditElement: (Int, String) -> Void
    let onDeleteElement: (Int, String) -> Void

    private var listRows: [ListRow] {
        rows.enumerated().map { index, row in
            ListRow(index: index, value: row.1)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(listRows) {
                TableColumn("Index") { row in
                    Text("[\(row.index)]")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .width(60)

                TableColumn("Value") { row in
                    Text(row.value)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                }

                TableColumn("Actions") { row in
                    HStack(spacing: 8) {
                        Button {
                            onEditElement(row.index, row.value)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Edit element")

                        Button {
                            onDeleteElement(row.index, row.value)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .help("Delete element")
                    }
                }
                .width(80)
            }

            Divider()

            HStack {
                Button {
                    onAddElement()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add element")

                Spacer()

                HStack(spacing: 4) {
                    Text("\(rows.count) elements")
                    if let valueSize {
                        Text("\u{00B7}")
                        Text(ByteCountFormatter.string(fromByteCount: Int64(valueSize), countStyle: .memory))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }
}

// MARK: - Set Detail View

struct SetRow: Identifiable {
    let id = UUID()
    let member: String
}

struct SetDetailView: View {
    let key: String
    let rows: [(String, String)]
    let valueSize: Int?
    let onAddMember: () -> Void
    let onDeleteMember: (String) -> Void

    private var setRows: [SetRow] {
        rows.map { SetRow(member: $0.1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(setRows) {
                TableColumn("Member") { row in
                    Text(row.member)
                        .font(.system(.body, design: .monospaced))
                }

                TableColumn("Actions") { row in
                    Button {
                        onDeleteMember(row.member)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help("Delete member")
                }
                .width(60)
            }

            Divider()

            HStack {
                Button {
                    onAddMember()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add member")

                Spacer()

                HStack(spacing: 4) {
                    Text("\(rows.count) members")
                    if let valueSize {
                        Text("\u{00B7}")
                        Text(ByteCountFormatter.string(fromByteCount: Int64(valueSize), countStyle: .memory))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }
}

// MARK: - ZSet Detail View

struct ZSetRow: Identifiable {
    let id = UUID()
    let score: String
    let member: String
}

struct ZSetDetailView: View {
    let key: String
    let rows: [(String, String)]
    let valueSize: Int?
    let onAddMember: () -> Void
    let onEditMember: (String, String) -> Void
    let onDeleteMember: (String) -> Void

    private var zsetRows: [ZSetRow] {
        rows.map { ZSetRow(score: $0.0, member: $0.1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(zsetRows) {
                TableColumn("Score") { row in
                    Text(row.score)
                        .font(.system(.body, design: .monospaced))
                }
                .width(100)

                TableColumn("Member") { row in
                    Text(row.member)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                }

                TableColumn("Actions") { row in
                    HStack(spacing: 8) {
                        Button {
                            onEditMember(row.member, row.score)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Edit score")

                        Button {
                            onDeleteMember(row.member)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .help("Delete member")
                    }
                }
                .width(80)
            }

            Divider()

            HStack {
                Button {
                    onAddMember()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add member")

                Spacer()

                HStack(spacing: 4) {
                    Text("\(rows.count) members")
                    if let valueSize {
                        Text("\u{00B7}")
                        Text(ByteCountFormatter.string(fromByteCount: Int64(valueSize), countStyle: .memory))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }
}

// MARK: - Edit Sheets

struct AddHashFieldSheet: View {
    let key: String
    @Binding var field: String
    @Binding var value: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Hash Field")
                .font(.headline)

            Form {
                TextField("Field name", text: $field)
                TextField("Value", text: $value, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Add") { onSave(field, value) }
                    .disabled(field.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

struct EditHashFieldSheet: View {
    let key: String
    let field: String
    @Binding var value: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Hash Field")
                .font(.headline)

            Form {
                HStack {
                    Text("Field")
                    Spacer()
                    Text(field)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                TextField("Value", text: $value, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Save") { onSave(field, value) }
            }
        }
        .padding()
        .frame(width: 400)
    }
}

struct AddListElementSheet: View {
    let key: String
    @Binding var value: String
    @Binding var position: KeyDetailView.ListPosition
    let onSave: (String, KeyDetailView.ListPosition) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add List Element")
                .font(.headline)

            Form {
                TextField("Value", text: $value, axis: .vertical)
                    .lineLimit(3...6)
                Picker("Position", selection: $position) {
                    Text("Head (LPUSH)").tag(KeyDetailView.ListPosition.head)
                    Text("Tail (RPUSH)").tag(KeyDetailView.ListPosition.tail)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Add") { onSave(value, position) }
                    .disabled(value.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

struct EditListElementSheet: View {
    let key: String
    let index: Int
    let value: String
    @State private var editValue: String
    let onSave: (Int, String) -> Void
    let onCancel: () -> Void

    init(key: String, index: Int, value: String, onSave: @escaping (Int, String) -> Void, onCancel: @escaping () -> Void) {
        self.key = key
        self.index = index
        self.value = value
        self._editValue = State(initialValue: value)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit List Element")
                .font(.headline)

            Form {
                HStack {
                    Text("Index")
                    Spacer()
                    Text("[\(index)]")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                TextField("Value", text: $editValue, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Save") { onSave(index, editValue) }
            }
        }
        .padding()
        .frame(width: 400)
    }
}

struct AddSetMemberSheet: View {
    let key: String
    @Binding var member: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Set Member")
                .font(.headline)

            Form {
                TextField("Member value", text: $member, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Add") { onSave(member) }
                    .disabled(member.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

struct AddZSetMemberSheet: View {
    let key: String
    @Binding var member: String
    @Binding var score: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Sorted Set Member")
                .font(.headline)

            Form {
                TextField("Member", text: $member)
                TextField("Score", text: $score)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Add") { onSave(member, score) }
                    .disabled(member.isEmpty || score.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

struct EditZSetMemberSheet: View {
    let key: String
    let member: String
    let score: String
    @State private var editScore: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    init(key: String, member: String, score: String, onSave: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        self.key = key
        self.member = member
        self.score = score
        self._editScore = State(initialValue: score)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit ZSet Score")
                .font(.headline)

            Form {
                HStack {
                    Text("Member")
                    Spacer()
                    Text(member)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                TextField("Score", text: $editScore)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Save") { onSave(member, editScore) }
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Editable Identifiers

extension String: @retroactive Identifiable {
    public var id: String { self }
}

extension KeyDetailView.ListPosition: Identifiable {
    var id: Int {
        switch self {
        case .head: return 0
        case .tail: return 1
        }
    }
}

struct ListElementEdit: Identifiable {
    let id = UUID()
    let index: Int
    let value: String
}

struct ZSetMemberEdit: Identifiable {
    let id = UUID()
    let member: String
    let score: String
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
