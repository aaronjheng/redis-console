import SwiftUI

struct BrowserView: View {
    @EnvironmentObject var app: ConnectionState
    @State private var searchText = ""
    @State private var typeFilter = ""
    @State private var showingAddKey = false
    @State private var newKeyName = ""
    @State private var newKeyType = "string"
    @State private var newKeyValue = ""

    var body: some View {
        PersistentSplitView(
            leftMinWidth: 250,
            rightMinWidth: 250
        ) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ZStack(alignment: .trailing) {
                        TextField("Pattern (e.g. user:* or *)", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                app.keyFilter = searchText.isEmpty ? "*" : searchText
                                Task { await app.scanKeys(reset: true) }
                            }
                        HStack(spacing: 4) {
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
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 8)
                        }
                    }
                }
                .padding(8)

                HStack {
                    Picker("", selection: $typeFilter) {
                        Text("All Types").tag("")
                        Text("String").tag("string")
                        Text("List").tag("list")
                        Text("Hash").tag("hash")
                        Text("Set").tag("set")
                        Text("Sorted Set").tag("zset")
                    }
                    .labelsHidden()
                    .onChange(of: typeFilter) { _, newValue in
                        app.keyTypeFilter = newValue
                    }
                    Spacer()
                    Button {
                        Task { await app.scanKeys(reset: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(app.isLoadingKeys)
                    .help("Refresh")
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

                Divider()

                let filteredKeys = app.keys.filter { app.keyTypeFilter.isEmpty || $0.type == app.keyTypeFilter }

                if app.isLoadingKeys && app.keys.isEmpty {
                    Spacer()
                    ProgressView("Scanning keys...")
                    Spacer()
                } else if app.keys.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "key.slash",
                        title: searchText.isEmpty ? "No keys found" : "No matching keys"
                    )
                    if app.hasMoreKeys {
                        if app.isLoadingKeys {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Scanning...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                        } else {
                            Button("Load more") {
                                Task { await app.scanKeys() }
                            }
                            .padding(8)
                        }
                    }
                    Spacer()
                } else if filteredKeys.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "key.slash",
                        title: "No matching keys"
                    )
                    if app.hasMoreKeys {
                        if app.isLoadingKeys {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Scanning...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                        } else {
                            Button("Load more") {
                                Task { await app.scanKeys() }
                            }
                            .padding(8)
                        }
                    }
                    Spacer()
                } else {
                    List(filteredKeys, selection: $app.selectedKey) { entry in
                        KeyRow(entry: entry)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    Task { await app.deleteKey(entry) }
                                }
                                Divider()
                                Button("Copy Key") {
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(entry.key, forType: .string)
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
                        if app.isLoadingKeys {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Scanning...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                        } else {
                            Button("Load more") {
                                Task { await app.scanKeys() }
                            }
                            .padding(8)
                        }
                    }
                }

                Divider()

                HStack {
                    Button {
                        newKeyName = ""
                        newKeyType = "string"
                        newKeyValue = ""
                        showingAddKey = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Add key")

                    Spacer()

                    Text("\(app.keys.count) keys")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
        } right: {
            KeyDetailView()
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
            let values = value.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            if !values.isEmpty {
                _ = try? await client.send(["RPUSH", name] + values)
            }
        case "hash":
            var args = ["HSET", name]
            for line in value.split(separator: "\n", omittingEmptySubsequences: true) {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    args.append(String(parts[0]))
                    args.append(String(parts[1]))
                }
            }
            if args.count > 2 {
                _ = try? await client.send(args)
            }
        case "set":
            let members = value.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            if !members.isEmpty {
                _ = try? await client.send(["SADD", name] + members)
            }
        case "zset":
            var args = ["ZADD", name]
            for line in value.split(separator: "\n", omittingEmptySubsequences: true) {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    args.append(String(parts[0]))
                    args.append(String(parts[1]))
                }
            }
            if args.count > 2 {
                _ = try? await client.send(args)
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
            if entry.type.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16)
            } else {
                Image(systemName: entry.icon)
                    .frame(width: 16)
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.key)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    if !entry.type.isEmpty {
                        Text(entry.type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppTheme.spacingSmall)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, AppTheme.spacingSmall)
    }
}

struct KeyDetailView: View {
    @EnvironmentObject var app: ConnectionState
    @State private var didCopyKey = false
    @State private var editingString = false
    @State private var stringValue = ""
    @State private var showingAddHashField = false
    @State private var newHashField = ""
    @State private var newHashValue = ""
    @State private var showingAddListElement = false
    @State private var newListElement = ""
    @State private var newListPosition: ListPosition = .head
    @State private var showingAddSetMember = false
    @State private var newSetMember = ""
    @State private var showingAddZSetMember = false
    @State private var newZSetMember = ""
    @State private var newZSetScore = ""

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
                            keySize: key.size,
                            onAddField: { showingAddHashField = true },
                            onSaveField: { field, value in
                                Task {
                                    await app.updateHashField(key: key.key, field: field, value: value)
                                    await app.refreshSelectedKey()
                                }
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

                    case "list":
                        ListDetailView(
                            key: key.key,
                            rows: app.keyDetailRows,
                            keySize: key.size,
                            onAddElement: { showingAddListElement = true },
                            onSaveElement: { index, value in
                                Task {
                                    await app.updateListElement(key: key.key, index: index, value: value)
                                    await app.refreshSelectedKey()
                                }
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

                    case "set":
                        SetDetailView(
                            key: key.key,
                            rows: app.keyDetailRows,
                            keySize: key.size,
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
                            keySize: key.size,
                            onAddMember: { showingAddZSetMember = true },
                            onSaveMember: { member, score in
                                Task {
                                    await app.updateZSetScore(key: key.key, member: member, score: score)
                                    await app.refreshSelectedKey()
                                }
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

                    default:
                        genericRowsView
                    }
                } else {
                    switch app.keyType {
                    case "string":
                        StringDetailView(
                            key: key.key,
                            value: app.keyDetail,
                            keySize: key.size,
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
                EmptyStateView(
                    icon: "sidebar.left",
                    title: "Select a key to view its value"
                )
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
                    Label(key.ttlText, systemImage: "clock")
                        .foregroundStyle(key.ttl == nil ? .secondary : Color.orange)
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
            .disabled(app.isLoadingDetail)
            .help("Refresh")

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(key.key, forType: .string)
                didCopyKey = true
                Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    didCopyKey = false
                }
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(didCopyKey ? .secondary : .primary)
            }
            .buttonStyle(.borderless)
            .disabled(app.isLoadingDetail)
            .help("Copy key")

            Button {
                Task {
                    _ = try? await app.activeClient?.send("EXPIRE", key.key, "3600")
                    await app.selectKey(key)
                }
            } label: {
                Image(systemName: "clock.badge.plus")
            }
            .buttonStyle(.borderless)
            .disabled(app.isLoadingDetail)
            .help("Set 1h TTL")

            Button(role: .destructive) {
                Task { await app.deleteKey(key) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(app.isLoadingDetail)
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
    let keySize: Int?
    let onSave: (String) -> Void

    @State private var isEditing = false
    @State private var editValue = ""
    @State private var isBeautified = false

    private var isJson: Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private var beautifiedValue: String {
        guard
            let data = value.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted),
            let prettyString = String(data: prettyData, encoding: .utf8)
        else {
            return value
        }
        return prettyString
    }

    private var displayedValue: String {
        isBeautified ? beautifiedValue : value
    }

    private var highlightedBeautifiedValue: AttributedString {
        JSONSyntaxHighlighter.highlight(beautifiedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isEditing {
                VStack(spacing: 8) {
                    TextEditor(text: $editValue)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.accentColor, lineWidth: 2)
                        )

                    HStack(spacing: 8) {
                        Spacer()
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
                .padding()
            } else {
                ZStack(alignment: .topTrailing) {
                    ScrollView {
                        Group {
                            if isBeautified && isJson {
                                Text(highlightedBeautifiedValue)
                            } else {
                                Text(displayedValue)
                            }
                        }
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                    .onTapGesture(count: 2) {
                        editValue = value
                        isEditing = true
                    }

                    HStack(spacing: 4) {
                        if isJson {
                            Button {
                                isBeautified.toggle()
                            } label: {
                                Image(systemName: isBeautified ? "text.alignleft" : "curlybraces")
                            }
                            .buttonStyle(.borderless)
                            .help(isBeautified ? "Show original" : "Beautify JSON")
                        }

                        Button {
                            editValue = value
                            isEditing = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Edit value")
                    }
                    .padding()
                }
            }

            if let keySize {
                Divider()
                HStack {
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(keySize), countStyle: .memory))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(AppTheme.spacing)
            }
        }
        .onAppear {
            isBeautified = isJson
        }
        .onChange(of: value) { _, _ in
            isBeautified = isJson
        }
    }
}

private enum JSONSyntaxHighlighter {
    static func highlight(_ source: String) -> AttributedString {
        var attributed = AttributedString(source)
        attributed.foregroundColor = .primary

        let chars = Array(source)
        var index = 0

        while index < chars.count {
            let char = chars[index]

            if char == "\"" {
                let stringStart = index
                index += 1
                var escapeRanges: [Range<Int>] = []

                while index < chars.count {
                    if chars[index] == "\\" {
                        let escapeStart = index
                        index += 1
                        if index < chars.count {
                            index += 1
                        }
                        escapeRanges.append(escapeStart..<index)
                        continue
                    }
                    if chars[index] == "\"" {
                        index += 1
                        break
                    }
                    index += 1
                }

                let stringRange = stringStart..<index
                let isObjectKey = isObjectKeyString(chars: chars, tokenRange: stringRange)
                applyColor(
                    to: &attributed,
                    source: source,
                    range: stringRange,
                    color: isObjectKey ? .teal : .green
                )
                for escapeRange in escapeRanges {
                    applyColor(to: &attributed, source: source, range: escapeRange, color: .orange)
                }
                continue
            }

            if isNumberStart(char: char, next: index + 1 < chars.count ? chars[index + 1] : nil) {
                let numberStart = index
                index += 1
                while index < chars.count, isNumberBody(char: chars[index]) {
                    index += 1
                }
                applyColor(to: &attributed, source: source, range: numberStart..<index, color: .blue)
                continue
            }

            if let keyword = keyword(at: index, chars: chars) {
                let end = index + keyword.count
                let color: Color =
                    switch keyword {
                    case "true", "false":
                        .orange
                    case "null":
                        .red
                    default:
                        .primary
                    }
                applyColor(to: &attributed, source: source, range: index..<end, color: color)
                index = end
                continue
            }

            if "{}[],:".contains(char) {
                applyColor(to: &attributed, source: source, range: index..<(index + 1), color: .secondary)
            }

            index += 1
        }

        return attributed
    }

    private static func applyColor(to attributed: inout AttributedString, source: String, range: Range<Int>, color: Color) {
        guard let lower = source.index(source.startIndex, offsetBy: range.lowerBound, limitedBy: source.endIndex),
            let upper = source.index(source.startIndex, offsetBy: range.upperBound, limitedBy: source.endIndex),
            let attributedRange = Range(lower..<upper, in: attributed)
        else {
            return
        }
        attributed[attributedRange].foregroundColor = color
    }

    private static func isObjectKeyString(chars: [Character], tokenRange: Range<Int>) -> Bool {
        var lookahead = tokenRange.upperBound
        while lookahead < chars.count, chars[lookahead].isWhitespace {
            lookahead += 1
        }
        return lookahead < chars.count && chars[lookahead] == ":"
    }

    private static func isNumberStart(char: Character, next: Character?) -> Bool {
        if char.isNumber {
            return true
        }
        if char == "-", let next, next.isNumber {
            return true
        }
        return false
    }

    private static func isNumberBody(char: Character) -> Bool {
        char.isNumber || char == "." || char == "e" || char == "E" || char == "+" || char == "-"
    }

    private static func keyword(at index: Int, chars: [Character]) -> String? {
        for keyword in ["true", "false", "null"] {
            let end = index + keyword.count
            guard end <= chars.count else { continue }
            if String(chars[index..<end]) != keyword { continue }
            let previous = index > 0 ? chars[index - 1] : nil
            let next = end < chars.count ? chars[end] : nil
            if let previous, isIdentifierCharacter(previous) {
                continue
            }
            if let next, isIdentifierCharacter(next) {
                continue
            }
            return keyword
        }
        return nil
    }

    private static func isIdentifierCharacter(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_"
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
    let keySize: Int?
    let onAddField: () -> Void
    let onSaveField: (String, String) -> Void
    let onDeleteField: (String) -> Void

    @State private var editingField: String?
    @State private var editValue = ""

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
                    EditableHashCell(
                        row: row,
                        editingField: $editingField,
                        editValue: $editValue,
                        onSaveField: onSaveField
                    )
                }

                TableColumn("Actions") { row in
                    HStack(spacing: AppTheme.spacing) {
                        Button {
                            editingField = row.field
                            editValue = row.value
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Edit field")

                        DeleteIconButton(
                            action: { onDeleteField(row.field) },
                            helpText: "Delete field"
                        )
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

                StatusFooterView(
                    countText: "\(rows.count) fields",
                    sizeText: keySize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) }
                )
            }
            .padding(AppTheme.spacing)
        }
    }
}

struct EditableHashCell: View {
    let row: HashRow
    @Binding var editingField: String?
    @Binding var editValue: String
    let onSaveField: (String, String) -> Void

    var body: some View {
        if editingField == row.field {
            InlineTextField(
                text: $editValue,
                onSubmit: { onSaveField(row.field, editValue) },
                onCancel: { editingField = nil }
            )
        } else {
            Text(row.value)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)
                .onTapGesture(count: 2) {
                    editingField = row.field
                    editValue = row.value
                }
        }
    }
}

// MARK: - List Detail View

struct ListRow: Identifiable {
    let id = UUID()
    let index: Int
    let value: String
}

struct EditableListCell: View {
    let row: ListRow
    @Binding var editingIndex: Int?
    @Binding var editValue: String
    let onSaveElement: (Int, String) -> Void

    var body: some View {
        if editingIndex == row.index {
            InlineTextField(
                text: $editValue,
                onSubmit: { onSaveElement(row.index, editValue) },
                onCancel: { editingIndex = nil }
            )
        } else {
            Text(row.value)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)
                .onTapGesture(count: 2) {
                    editingIndex = row.index
                    editValue = row.value
                }
        }
    }
}

struct InlineTextField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textField.delegate = context.coordinator
        textField.focusRingType = .none
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.window?.makeFirstResponder(nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: InlineTextField

        init(_ parent: InlineTextField) {
            self.parent = parent
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.onSubmit()
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
    }
}

struct ListDetailView: View {
    let key: String
    let rows: [(String, String)]
    let keySize: Int?
    let onAddElement: () -> Void
    let onSaveElement: (Int, String) -> Void
    let onDeleteElement: (Int, String) -> Void

    @State private var editingIndex: Int?
    @State private var editValue = ""

    private var listRows: [ListRow] {
        rows.enumerated().map { index, row in
            ListRow(index: index, value: row.1)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(listRows) {
                TableColumn("Index") { row in
                    Text("\(row.index)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .width(60)

                TableColumn("Value") { row in
                    EditableListCell(
                        row: row,
                        editingIndex: $editingIndex,
                        editValue: $editValue,
                        onSaveElement: onSaveElement
                    )
                }

                TableColumn("Actions") { row in
                    HStack(spacing: AppTheme.spacing) {
                        Button {
                            editingIndex = row.index
                            editValue = row.value
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Edit element")

                        DeleteIconButton(
                            action: { onDeleteElement(row.index, row.value) },
                            helpText: "Delete element"
                        )
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

                StatusFooterView(
                    countText: "\(rows.count) elements",
                    sizeText: keySize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) }
                )
            }
            .padding(AppTheme.spacing)
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
    let keySize: Int?
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
                    DeleteIconButton(
                        action: { onDeleteMember(row.member) },
                        helpText: "Delete member"
                    )
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

                StatusFooterView(
                    countText: "\(rows.count) members",
                    sizeText: keySize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) }
                )
            }
            .padding(AppTheme.spacing)
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
    let keySize: Int?
    let onAddMember: () -> Void
    let onSaveMember: (String, String) -> Void
    let onDeleteMember: (String) -> Void

    @State private var editingMember: String?
    @State private var editScore = ""

    private var zsetRows: [ZSetRow] {
        rows.map { ZSetRow(score: $0.0, member: $0.1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(zsetRows) {
                TableColumn("Score") { row in
                    EditableZSetCell(
                        row: row,
                        editingMember: $editingMember,
                        editScore: $editScore,
                        onSaveMember: onSaveMember
                    )
                }
                .width(100)

                TableColumn("Member") { row in
                    Text(row.member)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                }

                TableColumn("Actions") { row in
                    HStack(spacing: AppTheme.spacing) {
                        Button {
                            editingMember = row.member
                            editScore = row.score
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Edit score")

                        DeleteIconButton(
                            action: { onDeleteMember(row.member) },
                            helpText: "Delete member"
                        )
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

                StatusFooterView(
                    countText: "\(rows.count) members",
                    sizeText: keySize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) }
                )
            }
            .padding(AppTheme.spacing)
        }
    }
}

struct EditableZSetCell: View {
    let row: ZSetRow
    @Binding var editingMember: String?
    @Binding var editScore: String
    let onSaveMember: (String, String) -> Void

    var body: some View {
        if editingMember == row.member {
            InlineTextField(
                text: $editScore,
                onSubmit: { onSaveMember(row.member, editScore) },
                onCancel: { editingMember = nil }
            )
        } else {
            Text(row.score)
                .font(.system(.body, design: .monospaced))
                .onTapGesture(count: 2) {
                    editingMember = row.member
                    editScore = row.score
                }
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
        SheetLayout(
            title: "Add Hash Field",
            cancelAction: onCancel,
            primaryActionTitle: "Add",
            isPrimaryDisabled: field.isEmpty,
            primaryAction: { onSave(field, value) },
            content: {
                Form {
                    TextField("Field name", text: $field)
                    TextField("Value", text: $value, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
        )
    }
}

struct AddListElementSheet: View {
    let key: String
    @Binding var value: String
    @Binding var position: KeyDetailView.ListPosition
    let onSave: (String, KeyDetailView.ListPosition) -> Void
    let onCancel: () -> Void

    var body: some View {
        SheetLayout(
            title: "Add List Element",
            cancelAction: onCancel,
            primaryActionTitle: "Add",
            isPrimaryDisabled: value.isEmpty,
            primaryAction: { onSave(value, position) },
            content: {
                Form {
                    TextField("Value", text: $value, axis: .vertical)
                        .lineLimit(3...6)
                    Picker("Position", selection: $position) {
                        Text("Head (LPUSH)").tag(KeyDetailView.ListPosition.head)
                        Text("Tail (RPUSH)").tag(KeyDetailView.ListPosition.tail)
                    }
                }
            }
        )
    }
}

struct AddSetMemberSheet: View {
    let key: String
    @Binding var member: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        SheetLayout(
            title: "Add Set Member",
            cancelAction: onCancel,
            primaryActionTitle: "Add",
            isPrimaryDisabled: member.isEmpty,
            primaryAction: { onSave(member) },
            content: {
                Form {
                    TextField("Member value", text: $member, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
        )
    }
}

struct AddZSetMemberSheet: View {
    let key: String
    @Binding var member: String
    @Binding var score: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        SheetLayout(
            title: "Add Sorted Set Member",
            cancelAction: onCancel,
            primaryActionTitle: "Add",
            isPrimaryDisabled: member.isEmpty || score.isEmpty,
            primaryAction: { onSave(member, score) },
            content: {
                Form {
                    TextField("Member", text: $member)
                    TextField("Score", text: $score)
                }
            }
        )
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

struct AddKeySheet: View {
    @Binding var keyName: String
    @Binding var keyType: String
    @Binding var keyValue: String
    let onSave: (String, String, String) -> Void
    let onCancel: () -> Void

    @State private var listValues: [String] = [""]
    @State private var hashPairs: [(field: String, value: String)] = [("", "")]
    @State private var setMembers: [String] = [""]
    @State private var zsetPairs: [(score: String, member: String)] = [("", "")]

    private func resetArrays(for type: String) {
        switch type {
        case "list": listValues = [""]
        case "hash": hashPairs = [("", "")]
        case "set": setMembers = [""]
        case "zset": zsetPairs = [("", "")]
        default: break
        }
    }

    var body: some View {
        SheetLayout(
            title: "Add New Key",
            cancelAction: onCancel,
            primaryActionTitle: "Add",
            isPrimaryDisabled: keyName.isEmpty,
            primaryAction: {
                switch keyType {
                case "list":
                    onSave(keyName, keyType, listValues.joined(separator: "\n"))
                case "hash":
                    let pairs = hashPairs.map { "\($0.field):\($0.value)" }.joined(separator: "\n")
                    onSave(keyName, keyType, pairs)
                case "set":
                    onSave(keyName, keyType, setMembers.joined(separator: "\n"))
                case "zset":
                    let pairs = zsetPairs.map { "\($0.score):\($0.member)" }.joined(separator: "\n")
                    onSave(keyName, keyType, pairs)
                default:
                    onSave(keyName, keyType, keyValue)
                }
            },
            content: {
                Form {
                    TextField("Key name", text: $keyName)
                    Picker("Type", selection: $keyType) {
                        Text("String").tag("string")
                        Text("List").tag("list")
                        Text("Hash").tag("hash")
                        Text("Set").tag("set")
                        Text("Sorted Set").tag("zset")
                    }
                    .onChange(of: keyType) { _, newValue in
                        resetArrays(for: newValue)
                    }

                    switch keyType {
                    case "list":
                        dynamicValueRows(
                            values: $listValues,
                            placeholder: { "Value \($0 + 1)" },
                            addLabel: "Add Value"
                        )
                    case "hash":
                        dynamicPairRows(
                            pairs: $hashPairs,
                            firstPlaceholder: "Field",
                            secondPlaceholder: "Value",
                            addLabel: "Add Field"
                        )
                    case "set":
                        dynamicValueRows(
                            values: $setMembers,
                            placeholder: { "Member \($0 + 1)" },
                            addLabel: "Add Member"
                        )
                    case "zset":
                        dynamicZSetRows(
                            pairs: $zsetPairs,
                            addLabel: "Add Member"
                        )
                    default:
                        TextField("Value", text: $keyValue, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
            }
        )
        .onAppear {
            resetArrays(for: keyType)
        }
    }

    @ViewBuilder
    private func dynamicValueRows(
        values: Binding<[String]>,
        placeholder: @escaping (Int) -> String,
        addLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(values.wrappedValue.enumerated()), id: \.offset) { index, _ in
                HStack {
                    TextField(
                        placeholder(index),
                        text: Binding(
                            get: { values.wrappedValue[index] },
                            set: { values.wrappedValue[index] = $0 }
                        ))
                    if values.wrappedValue.count > 1 {
                        Button {
                            values.wrappedValue.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Button {
                values.wrappedValue.append("")
            } label: {
                Label(addLabel, systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func dynamicPairRows(
        pairs: Binding<[(field: String, value: String)]>,
        firstPlaceholder: String,
        secondPlaceholder: String,
        addLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(pairs.wrappedValue.enumerated()), id: \.offset) { index, _ in
                HStack {
                    TextField(
                        firstPlaceholder,
                        text: Binding(
                            get: { pairs.wrappedValue[index].field },
                            set: { pairs.wrappedValue[index].field = $0 }
                        ))
                    TextField(
                        secondPlaceholder,
                        text: Binding(
                            get: { pairs.wrappedValue[index].value },
                            set: { pairs.wrappedValue[index].value = $0 }
                        ))
                    if pairs.wrappedValue.count > 1 {
                        Button {
                            pairs.wrappedValue.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Button {
                pairs.wrappedValue.append(("", ""))
            } label: {
                Label(addLabel, systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func dynamicZSetRows(
        pairs: Binding<[(score: String, member: String)]>,
        addLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(pairs.wrappedValue.enumerated()), id: \.offset) { index, _ in
                HStack {
                    TextField(
                        "Score",
                        text: Binding(
                            get: { pairs.wrappedValue[index].score },
                            set: { pairs.wrappedValue[index].score = $0 }
                        )
                    )
                    .frame(width: 80)
                    TextField(
                        "Member",
                        text: Binding(
                            get: { pairs.wrappedValue[index].member },
                            set: { pairs.wrappedValue[index].member = $0 }
                        ))
                    if pairs.wrappedValue.count > 1 {
                        Button {
                            pairs.wrappedValue.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Button {
                pairs.wrappedValue.append(("", ""))
            } label: {
                Label(addLabel, systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }
}
