import SwiftUI

private func copyToPasteboard(_ value: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(value, forType: .string)
}

struct BrowserView: View {
    @EnvironmentObject var app: ConnectionState
    @State private var searchText = ""
    @State private var showingAddKey = false
    @State private var keyPendingDeletion: RedisKeyEntry?
    @State private var bulkDeletePreview: BulkDeletePreview?
    @State private var bulkDeleteResult: BulkDeleteResult?
    @State private var isPreparingBulkDelete = false
    @State private var isDeletingBulkKeys = false
    @State private var newKeyName = ""
    @State private var newKeyType = "string"
    @State private var newKeyValue = ""
    @State private var expandedNamespaces: Set<String> = []

    private let listScanCount = 500
    private let treeScanCount = 10_000

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
                                app.keyScanCount = currentScanCount
                                Task { await app.scanKeys(reset: true) }
                            }
                        HStack(spacing: 4) {
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                    app.keyFilter = "*"
                                    app.keyScanCount = currentScanCount
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
                    Picker("", selection: $app.keyTypeFilter) {
                        Text("All Types").tag("")
                        Text("String").tag("string")
                        Text("List").tag("list")
                        Text("Hash").tag("hash")
                        Text("Set").tag("set")
                        Text("Sorted Set").tag("zset")
                    }
                    .labelsHidden()
                    Spacer()
                    Toggle("Namespaces", isOn: $app.isNamespaceGroupingEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: app.isNamespaceGroupingEnabled) { _, isEnabled in
                            app.keyScanCount = isEnabled ? treeScanCount : listScanCount
                            expandedNamespaces = []
                            Task { await app.scanKeys(reset: true) }
                        }
                        .help("Group keys by namespace")
                    if app.isNamespaceGroupingEnabled {
                        TextField(
                            ":",
                            text: Binding(
                                get: { app.namespaceSeparator },
                                set: { value in
                                    app.updateNamespaceSeparator(value)
                                    expandedNamespaces = []
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 38)
                        .help("Namespace separator")
                    }
                    Button {
                        app.keyScanCount = currentScanCount
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

                if let error = app.connectionError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                        Text(error)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            app.connectionError = nil
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .help("Dismiss")
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }

                Divider()

                let displayedKeys = filteredKeys

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
                                app.keyScanCount = currentScanCount
                                Task { await app.scanKeys() }
                            }
                            .padding(8)
                        }
                    }
                    Spacer()
                } else if displayedKeys.isEmpty {
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
                                app.keyScanCount = currentScanCount
                                Task { await app.scanKeys() }
                            }
                            .padding(8)
                        }
                    }
                    Spacer()
                } else {
                    Group {
                        if app.isNamespaceGroupingEnabled {
                            KeyNamespaceList(
                                tree: KeyNamespaceTree(entries: displayedKeys, separator: app.namespaceSeparator),
                                selectedKey: $app.selectedKey,
                                expandedNamespaces: $expandedNamespaces,
                                onDeleteKey: { keyPendingDeletion = $0 },
                                onCopyKey: copyKeyToPasteboard
                            )
                        } else {
                            KeyFlatList(
                                keys: displayedKeys,
                                selectedKey: $app.selectedKey,
                                onDeleteKey: { keyPendingDeletion = $0 },
                                onCopyKey: copyKeyToPasteboard
                            )
                        }
                    }
                    .onChange(of: app.selectedKey) { _, newValue in
                        if let key = newValue {
                            expandNamespaces(containing: key.key)
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
                                app.keyScanCount = currentScanCount
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

                    Button(role: .destructive) {
                        Task { await prepareBulkDelete() }
                    } label: {
                        if isPreparingBulkDelete || isDeletingBulkKeys {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "trash.slash")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isPreparingBulkDelete || isDeletingBulkKeys || app.keys.isEmpty)
                    .help("Bulk delete current filter")

                    Spacer()

                    Text(browserFooterText(displayedCount: displayedKeys.count))
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
        .confirmationDialog(
            "Bulk Delete Keys?",
            isPresented: Binding(
                get: { bulkDeletePreview != nil },
                set: { isPresented in
                    if !isPresented {
                        bulkDeletePreview = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let preview = bulkDeletePreview {
                Button("Delete \(preview.keys.count) Keys", role: .destructive) {
                    Task { await executeBulkDelete(preview) }
                    bulkDeletePreview = nil
                }
                .disabled(preview.keys.isEmpty)
            }
            Button("Cancel", role: .cancel) {
                bulkDeletePreview = nil
            }
        } message: {
            if let preview = bulkDeletePreview {
                Text(bulkDeletePreviewMessage(preview))
            }
        }
        .alert(
            "Bulk Delete Complete",
            isPresented: Binding(
                get: { bulkDeleteResult != nil },
                set: { isPresented in
                    if !isPresented {
                        bulkDeleteResult = nil
                    }
                }
            )
        ) {
            Button("OK") {
                bulkDeleteResult = nil
            }
        } message: {
            if let result = bulkDeleteResult {
                Text(bulkDeleteResultMessage(result))
            }
        }
        .confirmationDialog(
            "Delete Key?",
            isPresented: Binding(
                get: { keyPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        keyPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let key = keyPendingDeletion {
                Button("Delete", role: .destructive) {
                    Task { await app.deleteKey(key) }
                    keyPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) {
                keyPendingDeletion = nil
            }
        } message: {
            if let key = keyPendingDeletion {
                Text("This permanently deletes \(key.key).")
            }
        }
        .onAppear {
            app.keyScanCount = currentScanCount
            searchText = app.keyFilter == "*" ? "" : app.keyFilter
        }
    }

    private var filteredKeys: [RedisKeyEntry] {
        app.keys.filter { app.keyTypeFilter.isEmpty || $0.type == app.keyTypeFilter }
    }

    private var currentScanCount: Int {
        app.isNamespaceGroupingEnabled ? treeScanCount : listScanCount
    }

    private func copyKeyToPasteboard(_ entry: RedisKeyEntry) {
        copyToPasteboard(entry.key)
    }

    private func expandNamespaces(containing key: String) {
        var namespacePath: [String] = []
        for namespace in KeyNamespaceTree.namespaceSegments(for: key, separator: app.namespaceSeparator) {
            namespacePath.append(namespace)
            expandedNamespaces.insert(namespacePath.joined(separator: app.namespaceSeparator))
        }
    }

    private func browserFooterText(displayedCount: Int) -> String {
        let totalText = app.hasMoreKeys ? "total unknown" : "total \(app.keys.count)"
        let limitText = app.keyScanLimitReached ? " · threshold reached" : ""
        return "\(totalText) · \(app.keyScanReturnedCount) scanned · \(app.keys.count) loaded · \(displayedCount) shown\(limitText)"
    }

    private func prepareBulkDelete() async {
        isPreparingBulkDelete = true
        defer { isPreparingBulkDelete = false }

        do {
            let preview = try await app.previewBulkDelete(
                pattern: app.keyFilter,
                typeFilter: app.keyTypeFilter
            )
            bulkDeletePreview = preview
        } catch {
            app.connectionError = error.localizedDescription
        }
    }

    private func executeBulkDelete(_ preview: BulkDeletePreview) async {
        isDeletingBulkKeys = true
        defer { isDeletingBulkKeys = false }

        do {
            bulkDeleteResult = try await app.executeBulkDelete(preview)
        } catch {
            app.connectionError = error.localizedDescription
        }
    }

    private func bulkDeletePreviewMessage(_ preview: BulkDeletePreview) -> String {
        var parts = [
            "Pattern: \(preview.pattern)",
            "Type: \(preview.typeText)",
            "Matched: \(preview.keys.count)",
            "Scanned: \(preview.scannedCount)",
        ]
        if preview.didReachLimit {
            parts.append("Preview stopped at the scan threshold.")
        }
        return parts.joined(separator: "\n")
    }

    private func bulkDeleteResultMessage(_ result: BulkDeleteResult) -> String {
        var parts = [
            "Processed: \(result.processed)",
            "Deleted: \(result.deleted)",
            "Time: \(String(format: "%.2f", result.duration))s",
        ]
        if result.usedFallback {
            parts.append("Used DEL fallback.")
        }
        return parts.joined(separator: "\n")
    }

    private func addKey(name: String, type: String, value: String) async {
        guard let client = app.activeClient else { return }
        do {
            let existsResult = try await client.send("EXISTS", name)
            try throwIfRedisError(existsResult)
            guard existsResult.intValue == 0 else {
                throw RedisError.commandError("Key \"\(name)\" already exists")
            }

            switch type {
            case "string":
                let result = try await client.send("SET", name, value, "NX")
                try throwIfRedisError(result)
                guard result.string != nil else {
                    throw RedisError.commandError("Key \"\(name)\" already exists")
                }
            case "list":
                let values = value.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
                guard !values.isEmpty else {
                    throw RedisError.commandError("List key requires at least one value")
                }
                let result = try await client.send(["RPUSH", name] + values)
                try throwIfRedisError(result)
            case "hash":
                var args = ["HSET", name]
                for line in value.split(separator: "\n", omittingEmptySubsequences: true) {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        args.append(String(parts[0]))
                        args.append(String(parts[1]))
                    }
                }
                guard args.count > 2 else {
                    throw RedisError.commandError("Hash key requires at least one field")
                }
                let result = try await client.send(args)
                try throwIfRedisError(result)
            case "set":
                let members = value.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
                guard !members.isEmpty else {
                    throw RedisError.commandError("Set key requires at least one member")
                }
                let result = try await client.send(["SADD", name] + members)
                try throwIfRedisError(result)
            case "zset":
                var args = ["ZADD", name, "NX"]
                for line in value.split(separator: "\n", omittingEmptySubsequences: true) {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        args.append(String(parts[0]))
                        args.append(String(parts[1]))
                    }
                }
                guard args.count > 3 else {
                    throw RedisError.commandError("Sorted set key requires at least one member")
                }
                let result = try await client.send(args)
                try throwIfRedisError(result)
            default:
                let result = try await client.send("SET", name, value, "NX")
                try throwIfRedisError(result)
                guard result.string != nil else {
                    throw RedisError.commandError("Key \"\(name)\" already exists")
                }
            }
            app.connectionError = nil
            app.keyScanCount = currentScanCount
            await app.scanKeys(reset: true)
        } catch {
            app.connectionError = error.localizedDescription
            app.keyDetailError = error.localizedDescription
        }
    }

    private func throwIfRedisError(_ value: RESPValue) throws {
        if case .error(let message) = value {
            throw RedisError.commandError(message)
        }
    }
}

private struct KeyFlatList: View {
    let keys: [RedisKeyEntry]
    @Binding var selectedKey: RedisKeyEntry?
    let onDeleteKey: (RedisKeyEntry) -> Void
    let onCopyKey: (RedisKeyEntry) -> Void

    var body: some View {
        List(selection: $selectedKey) {
            ForEach(keys) { entry in
                KeyRow(entry: entry)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            onDeleteKey(entry)
                        }
                        Divider()
                        Button("Copy Key") {
                            onCopyKey(entry)
                        }
                    }
                    .tag(entry)
            }
        }
        .listStyle(.plain)
    }
}

private struct KeyNamespaceList: View {
    let tree: KeyNamespaceTree
    @Binding var selectedKey: RedisKeyEntry?
    @Binding var expandedNamespaces: Set<String>
    let onDeleteKey: (RedisKeyEntry) -> Void
    let onCopyKey: (RedisKeyEntry) -> Void

    var body: some View {
        List(selection: $selectedKey) {
            ForEach(tree.rootKeys) { entry in
                KeyRow(entry: entry)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            onDeleteKey(entry)
                        }
                        Divider()
                        Button("Copy Key") {
                            onCopyKey(entry)
                        }
                    }
                    .tag(entry)
            }

            ForEach(tree.namespaces) { namespace in
                KeyNamespaceNodeView(
                    namespace: namespace,
                    separator: tree.separator,
                    selectedKey: $selectedKey,
                    expandedNamespaces: $expandedNamespaces,
                    onDeleteKey: onDeleteKey,
                    onCopyKey: onCopyKey
                )
            }
        }
        .listStyle(.plain)
    }
}

private struct KeyNamespaceNodeView: View {
    let namespace: KeyNamespaceNode
    let separator: String
    @Binding var selectedKey: RedisKeyEntry?
    @Binding var expandedNamespaces: Set<String>
    let onDeleteKey: (RedisKeyEntry) -> Void
    let onCopyKey: (RedisKeyEntry) -> Void

    var body: some View {
        DisclosureGroup(isExpanded: namespaceExpansion) {
            ForEach(namespace.children) { childNamespace in
                KeyNamespaceNodeView(
                    namespace: childNamespace,
                    separator: separator,
                    selectedKey: $selectedKey,
                    expandedNamespaces: $expandedNamespaces,
                    onDeleteKey: onDeleteKey,
                    onCopyKey: onCopyKey
                )
            }

            ForEach(namespace.keys) { entry in
                KeyRow(entry: entry, displayName: KeyNamespaceTree.leafName(for: entry.key, separator: separator))
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            onDeleteKey(entry)
                        }
                        Divider()
                        Button("Copy Key") {
                            onCopyKey(entry)
                        }
                    }
                    .tag(entry)
            }
        } label: {
            KeyNamespaceRow(namespace: namespace)
        }
    }

    private var namespaceExpansion: Binding<Bool> {
        Binding {
            expandedNamespaces.contains(namespace.id)
        } set: { isExpanded in
            if isExpanded {
                expandedNamespaces.insert(namespace.id)
            } else {
                expandedNamespaces.remove(namespace.id)
            }
        }
    }
}

private struct KeyNamespaceRow: View {
    let namespace: KeyNamespaceNode

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.tint)
            Text(namespace.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("\(namespace.keyCount)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, AppTheme.spacing)
        .accessibilityLabel("\(namespace.name), \(namespace.keyCount) keys")
    }
}

private struct KeyNamespaceTree {
    let rootKeys: [RedisKeyEntry]
    let namespaces: [KeyNamespaceNode]
    let separator: String

    init(entries: [RedisKeyEntry], separator: String) {
        self.separator = KeyNamespaceTree.normalizedSeparator(separator)
        var root = KeyNamespaceNode.root
        for entry in entries {
            root.insert(entry, separator: self.separator)
        }
        root.sortRecursively()
        rootKeys = root.keys
        namespaces = root.children
    }

    static func namespaceSegments(for key: String, separator: String) -> [String] {
        let separatorCharacter = Character(normalizedSeparator(separator))
        let segments = key.split(separator: separatorCharacter, omittingEmptySubsequences: false).map(String.init)
        guard segments.count > 1 else { return [] }
        return segments.dropLast().filter { !$0.isEmpty }
    }

    static func leafName(for key: String, separator: String) -> String {
        let separatorCharacter = Character(normalizedSeparator(separator))
        guard let separatorIndex = key.lastIndex(of: separatorCharacter) else { return key }

        let suffixStart = key.index(after: separatorIndex)
        let suffix = String(key[suffixStart...])
        return suffix.isEmpty ? key : suffix
    }

    static func normalizedSeparator(_ value: String) -> String {
        String(value.first ?? ":")
    }
}

private struct KeyNamespaceNode: Identifiable {
    let id: String
    let name: String
    var keys: [RedisKeyEntry] = []
    var children: [KeyNamespaceNode] = []

    static var root: KeyNamespaceNode {
        KeyNamespaceNode(id: "", name: "")
    }

    var keyCount: Int {
        keys.count + children.reduce(0) { $0 + $1.keyCount }
    }

    mutating func insert(_ entry: RedisKeyEntry, separator: String) {
        insert(
            entry,
            namespaceSegments: KeyNamespaceTree.namespaceSegments(for: entry.key, separator: separator),
            segmentIndex: 0,
            separator: separator
        )
    }

    mutating func sortRecursively() {
        keys.sort { lhs, rhs in
            lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
        }
        children.sort { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        for index in children.indices {
            children[index].sortRecursively()
        }
    }

    private mutating func insert(
        _ entry: RedisKeyEntry,
        namespaceSegments: [String],
        segmentIndex: Int,
        separator: String
    ) {
        guard segmentIndex < namespaceSegments.count else {
            keys.append(entry)
            return
        }

        let namespaceName = namespaceSegments[segmentIndex]
        let namespaceID = id.isEmpty ? namespaceName : "\(id)\(separator)\(namespaceName)"
        if let childIndex = children.firstIndex(where: { $0.id == namespaceID }) {
            children[childIndex].insert(
                entry,
                namespaceSegments: namespaceSegments,
                segmentIndex: segmentIndex + 1,
                separator: separator
            )
        } else {
            var child = KeyNamespaceNode(id: namespaceID, name: namespaceName)
            child.insert(
                entry,
                namespaceSegments: namespaceSegments,
                segmentIndex: segmentIndex + 1,
                separator: separator
            )
            children.append(child)
        }
    }
}

struct KeyRow: View {
    let entry: RedisKeyEntry
    var displayName: String?

    var body: some View {
        HStack(spacing: 8) {
            if entry.type.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 42)
            } else {
                Text(entry.type)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppTheme.spacingSmall)
                    .padding(.vertical, 1)
                    .frame(minWidth: 42)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
            }
            Text(displayName ?? entry.key)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.vertical, AppTheme.spacing)
        .help(entry.key)
        .accessibilityLabel(entry.key)
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
    @State private var keyPendingDeletion: RedisKeyEntry?
    @State private var showingTTLEditor = false
    @State private var ttlInput = ""
    @State private var ttlEditorError: String?
    @State private var isAutoRefreshEnabled = false
    @State private var autoRefreshInterval = 5

    private let maxTTL = 2_147_483_647

    enum ListPosition {
        case head, tail
    }

    var body: some View {
        VStack(spacing: 0) {
            if let key = app.selectedKey {
                headerView(key: key)

                Divider()

                if let error = app.keyDetailError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                        Text(error)
                            .lineLimit(2)
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.vertical, 6)

                    Divider()
                }

                if app.isLoadingDetail {
                    Spacer()
                    ProgressView("Loading value...")
                    Spacer()
                } else {
                    detailContent(key: key)
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
        .confirmationDialog(
            "Delete Key?",
            isPresented: Binding(
                get: { keyPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        keyPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let key = keyPendingDeletion {
                Button("Delete", role: .destructive) {
                    Task { await app.deleteKey(key) }
                    keyPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) {
                keyPendingDeletion = nil
            }
        } message: {
            if let key = keyPendingDeletion {
                Text("This permanently deletes \(key.key).")
            }
        }
        .onChange(of: app.selectedKey?.key) {
            showingTTLEditor = false
            ttlEditorError = nil
        }
        .task(id: autoRefreshTaskID) {
            guard isAutoRefreshEnabled else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(autoRefreshInterval))
                guard !Task.isCancelled, app.selectedKey != nil, !app.isLoadingDetail else { continue }
                await app.refreshSelectedKey()
            }
        }
    }

    private var autoRefreshTaskID: String {
        "\(app.selectedKey?.key ?? "")|\(isAutoRefreshEnabled)|\(autoRefreshInterval)"
    }

    @ViewBuilder
    private func detailContent(key: RedisKeyEntry) -> some View {
        switch app.keyType {
        case "string":
            StringDetailView(
                key: key.key,
                value: app.keyDetail,
                keySize: app.valueSize ?? key.size,
                format: Binding(
                    get: { app.stringValueFormat },
                    set: { app.stringValueFormat = $0 }
                ),
                onSave: { value in
                    Task {
                        await app.updateStringValue(key: key.key, value: value)
                        await app.refreshSelectedKey()
                    }
                }
            )

        case "hash":
            HashDetailView(
                key: key.key,
                rows: app.keyDetailRows,
                keySize: app.valueSize ?? key.size,
                keyLength: app.keyDetailLength ?? key.length,
                searchText: app.keyDetailSearchText,
                hasMoreRows: app.keyDetailHasMoreRows,
                onSearch: { text in
                    Task { await app.searchSelectedKeyDetail(text) }
                },
                onLoadMore: {
                    Task { await app.loadMoreSelectedKeyDetailRows() }
                },
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
                keySize: app.valueSize ?? key.size,
                keyLength: app.keyDetailLength ?? key.length,
                hasMoreRows: app.keyDetailHasMoreRows,
                onLoadMore: {
                    Task { await app.loadMoreSelectedKeyDetailRows() }
                },
                onAddElement: { showingAddListElement = true },
                onSaveElement: { index, value in
                    Task {
                        await app.updateListElement(key: key.key, index: index, value: value)
                        await app.refreshSelectedKey()
                    }
                },
                onDeleteElement: { index, _ in
                    Task {
                        await app.deleteListElement(key: key.key, index: index)
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
                keySize: app.valueSize ?? key.size,
                keyLength: app.keyDetailLength ?? key.length,
                searchText: app.keyDetailSearchText,
                hasMoreRows: app.keyDetailHasMoreRows,
                onSearch: { text in
                    Task { await app.searchSelectedKeyDetail(text) }
                },
                onLoadMore: {
                    Task { await app.loadMoreSelectedKeyDetailRows() }
                },
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
                keySize: app.valueSize ?? key.size,
                keyLength: app.keyDetailLength ?? key.length,
                searchText: app.keyDetailSearchText,
                order: app.keyDetailZSetOrder,
                hasMoreRows: app.keyDetailHasMoreRows,
                onSearch: { text in
                    Task { await app.searchSelectedKeyDetail(text) }
                },
                onOrderChange: { order in
                    Task { await app.updateSelectedZSetOrder(order) }
                },
                onLoadMore: {
                    Task { await app.loadMoreSelectedKeyDetailRows() }
                },
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
            if app.keyDetailRows.isEmpty {
                emptyValueView
            } else {
                genericRowsView
            }
        }
    }

    private func headerView(key: RedisKeyEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(key.key)
                    .font(.title3)
                    .lineLimit(1)
                HStack(spacing: 12) {
                    Label(key.type, systemImage: key.icon)
                        .foregroundStyle(.secondary)
                    if let length = app.keyDetailLength ?? key.length {
                        Label("Length: \(length)", systemImage: "number")
                            .foregroundStyle(.secondary)
                    }
                    if let size = app.valueSize ?? key.size {
                        Label(
                            ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .memory),
                            systemImage: "memorychip"
                        )
                        .foregroundStyle(.secondary)
                    }
                    if let refreshedAt = app.keyDetailLastRefreshedAt {
                        Label {
                            Text(refreshedAt, style: .time)
                        } icon: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .foregroundStyle(.secondary)
                    }
                    Button {
                        beginEditingTTL(for: key)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text("TTL: \(key.ttlText)")
                            Image(systemName: "pencil")
                                .imageScale(.small)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(key.hasExpiry ? Color.orange : .secondary)
                    .disabled(app.isLoadingDetail)
                    .accessibilityLabel("Edit TTL, \(key.ttlText)")
                    .help("Edit TTL")
                    .popover(isPresented: $showingTTLEditor, arrowEdge: .bottom) {
                        KeyTTLEditorPopover(
                            keyName: key.key,
                            ttlInput: $ttlInput,
                            error: ttlEditorError,
                            onSave: { saveTTL(for: key) },
                            onCancel: cancelTTLEdit
                        )
                        .onChange(of: ttlInput) { _, newValue in
                            let validatedValue = validatedTTLInput(newValue)
                            if validatedValue != newValue {
                                ttlInput = validatedValue
                            }
                            ttlEditorError = nil
                        }
                    }
                }
                .font(.caption)
            }
            Spacer()
            Toggle(
                isOn: $isAutoRefreshEnabled,
                label: {
                    Image(systemName: "timer")
                }
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(app.isLoadingDetail)
            .help("Auto refresh")

            Picker(
                "",
                selection: $autoRefreshInterval
            ) {
                Text("2s").tag(2)
                Text("5s").tag(5)
                Text("10s").tag(10)
                Text("30s").tag(30)
            }
            .labelsHidden()
            .frame(width: 74)
            .disabled(!isAutoRefreshEnabled || app.isLoadingDetail)
            .help("Refresh interval")

            Button {
                Task { await app.refreshSelectedKey() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(app.isLoadingDetail)
            .help("Refresh")

            Button {
                copyToPasteboard(key.key)
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

            Button(role: .destructive) {
                keyPendingDeletion = key
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(app.isLoadingDetail)
            .help("Delete key")
        }
        .padding()
    }

    private func beginEditingTTL(for key: RedisKeyEntry) {
        if let ttl = key.ttl, ttl > 0 {
            ttlInput = "\(ttl)"
        } else {
            ttlInput = ""
        }
        ttlEditorError = nil
        showingTTLEditor = true
    }

    private func cancelTTLEdit() {
        ttlEditorError = nil
        showingTTLEditor = false
    }

    private func saveTTL(for key: RedisKeyEntry) {
        let ttl = ttlInput.isEmpty ? -1 : Int(ttlInput)
        guard let ttl else {
            ttlEditorError = "Enter a valid TTL."
            return
        }

        showingTTLEditor = false
        ttlEditorError = nil
        Task {
            await app.updateKeyTTL(key, ttl: ttl)
        }
    }

    private func validatedTTLInput(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        guard let ttl = Int(digits) else {
            return digits
        }
        return min(ttl, maxTTL).description
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
                            .copyableCell(row.0, row: "\(row.0)\t\(row.1)")
                        Text(row.1)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .copyableCell(row.1, row: "\(row.0)\t\(row.1)")
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

private struct KeyTTLEditorPopover: View {
    let keyName: String
    @Binding var ttlInput: String
    let error: String?
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(keyName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Text("TTL")
                    .font(.headline)
                TextField("No limit", text: $ttlInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .onSubmit(onSave)
                Text("s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 260)
    }
}

// MARK: - String Detail View

struct StringDetailView: View {
    let key: String
    let value: String
    let keySize: Int?
    @Binding var format: StringValueFormat
    let onSave: (String) -> Void

    @State private var isEditing = false
    @State private var editValue = ""

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
        switch format {
        case .raw:
            return value
        case .unicode:
            return unicodeEscapedValue
        case .json:
            return isJson ? beautifiedValue : value
        case .ascii:
            return asciiValue
        case .hex:
            return hexValue
        }
    }

    private var highlightedBeautifiedValue: AttributedString {
        JSONSyntaxHighlighter.highlight(beautifiedValue)
    }

    private var unicodeEscapedValue: String {
        value.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0x0A:
                return "\\n"
            case 0x0D:
                return "\\r"
            case 0x09:
                return "\\t"
            case 0x20...0x7E:
                return String(scalar)
            default:
                return "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
            }
        }.joined()
    }

    private var asciiValue: String {
        String(
            value.utf8.map { byte in
                if (32...126).contains(byte), let scalar = UnicodeScalar(Int(byte)) {
                    return Character(scalar)
                }
                return "."
            }
        )
    }

    private var hexValue: String {
        value.utf8.enumerated().map { index, byte in
            let separator = index > 0 && index % 16 == 0 ? "\n" : " "
            let prefix = index == 0 ? "" : separator
            return prefix + String(format: "%02X", byte)
        }.joined()
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
                            if format == .json && isJson {
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
                        Picker("", selection: $format) {
                            ForEach(StringValueFormat.allCases) { format in
                                Text(format.title).tag(format)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        .help("Value format")

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

// MARK: - Collection Detail Controls

private func detailCountText(loaded: Int, total: Int?, noun: String) -> String {
    if let total {
        return "\(loaded) / \(total) \(noun)"
    }
    return "\(loaded) \(noun)"
}

private struct DetailSearchField: View {
    @Binding var searchText: String
    let placeholder: String
    let onSearch: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $searchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onSearch)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    onSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Clear filter")
            }

            Button {
                onSearch()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Search")
        }
    }
}

private struct CopyableCellModifier: ViewModifier {
    let cellValue: String
    let rowValue: String

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Copy Cell") {
                copyToPasteboard(cellValue)
            }
            Button("Copy Row") {
                copyToPasteboard(rowValue)
            }
        }
    }
}

extension View {
    fileprivate func copyableCell(_ cellValue: String, row: String) -> some View {
        modifier(CopyableCellModifier(cellValue: cellValue, rowValue: row))
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
    let keyLength: Int?
    let searchText: String
    let hasMoreRows: Bool
    let onSearch: (String) -> Void
    let onLoadMore: () -> Void
    let onAddField: () -> Void
    let onSaveField: (String, String) -> Void
    let onDeleteField: (String) -> Void

    @State private var editingField: String?
    @State private var editValue = ""
    @State private var pendingSearchText = ""

    private var hashRows: [HashRow] {
        rows.map { HashRow(field: $0.0, value: $0.1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailSearchField(
                searchText: $pendingSearchText,
                placeholder: "Field filter",
                onSearch: { onSearch(pendingSearchText) }
            )
            .padding(AppTheme.spacing)

            Divider()

            Table(hashRows) {
                TableColumn("Field") { row in
                    Text(row.field)
                        .font(.system(.body, design: .monospaced))
                        .copyableCell(row.field, row: "\(row.field)\t\(row.value)")
                }
                .width(min: 100, ideal: 150, max: 300)

                TableColumn("Value") { row in
                    EditableHashCell(
                        row: row,
                        editingField: $editingField,
                        editValue: $editValue,
                        rowValue: "\(row.field)\t\(row.value)",
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

                if hasMoreRows {
                    Button("Load more") {
                        onLoadMore()
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                StatusFooterView(
                    countText: detailCountText(loaded: rows.count, total: keyLength, noun: "fields"),
                    sizeText: keySize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) }
                )
            }
            .padding(AppTheme.spacing)
        }
        .onAppear {
            pendingSearchText = searchText
        }
        .onChange(of: searchText) { _, newValue in
            pendingSearchText = newValue
        }
    }
}

struct EditableHashCell: View {
    let row: HashRow
    @Binding var editingField: String?
    @Binding var editValue: String
    let rowValue: String
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
                .copyableCell(row.value, row: rowValue)
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
    let rowValue: String
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
                .copyableCell(row.value, row: rowValue)
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
    let keyLength: Int?
    let hasMoreRows: Bool
    let onLoadMore: () -> Void
    let onAddElement: () -> Void
    let onSaveElement: (Int, String) -> Void
    let onDeleteElement: (Int, String) -> Void

    @State private var editingIndex: Int?
    @State private var editValue = ""

    private var listRows: [ListRow] {
        rows.compactMap { row in
            guard let index = Int(row.0) else { return nil }
            return ListRow(index: index, value: row.1)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(listRows) {
                TableColumn("Index") { row in
                    Text("\(row.index)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .copyableCell("\(row.index)", row: "\(row.index)\t\(row.value)")
                }
                .width(60)

                TableColumn("Value") { row in
                    EditableListCell(
                        row: row,
                        editingIndex: $editingIndex,
                        editValue: $editValue,
                        rowValue: "\(row.index)\t\(row.value)",
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

                if hasMoreRows {
                    Button("Load more") {
                        onLoadMore()
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                StatusFooterView(
                    countText: detailCountText(loaded: rows.count, total: keyLength, noun: "elements"),
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
    let keyLength: Int?
    let searchText: String
    let hasMoreRows: Bool
    let onSearch: (String) -> Void
    let onLoadMore: () -> Void
    let onAddMember: () -> Void
    let onDeleteMember: (String) -> Void

    @State private var pendingSearchText = ""

    private var setRows: [SetRow] {
        rows.map { SetRow(member: $0.1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailSearchField(
                searchText: $pendingSearchText,
                placeholder: "Member filter",
                onSearch: { onSearch(pendingSearchText) }
            )
            .padding(AppTheme.spacing)

            Divider()

            Table(setRows) {
                TableColumn("Member") { row in
                    Text(row.member)
                        .font(.system(.body, design: .monospaced))
                        .copyableCell(row.member, row: row.member)
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

                if hasMoreRows {
                    Button("Load more") {
                        onLoadMore()
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                StatusFooterView(
                    countText: detailCountText(loaded: rows.count, total: keyLength, noun: "members"),
                    sizeText: keySize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) }
                )
            }
            .padding(AppTheme.spacing)
        }
        .onAppear {
            pendingSearchText = searchText
        }
        .onChange(of: searchText) { _, newValue in
            pendingSearchText = newValue
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
    let keyLength: Int?
    let searchText: String
    let order: KeyDetailZSetOrder
    let hasMoreRows: Bool
    let onSearch: (String) -> Void
    let onOrderChange: (KeyDetailZSetOrder) -> Void
    let onLoadMore: () -> Void
    let onAddMember: () -> Void
    let onSaveMember: (String, String) -> Void
    let onDeleteMember: (String) -> Void

    @State private var editingMember: String?
    @State private var editScore = ""
    @State private var pendingSearchText = ""

    private var zsetRows: [ZSetRow] {
        rows.map { ZSetRow(score: $0.0, member: $0.1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                DetailSearchField(
                    searchText: $pendingSearchText,
                    placeholder: "Member filter",
                    onSearch: { onSearch(pendingSearchText) }
                )

                Picker(
                    "",
                    selection: Binding(
                        get: { order },
                        set: { onOrderChange($0) }
                    )
                ) {
                    ForEach(KeyDetailZSetOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 180)
                .disabled(!pendingSearchText.isEmpty)
                .help("Sort order")
            }
            .padding(AppTheme.spacing)

            Divider()

            Table(zsetRows) {
                TableColumn("Score") { row in
                    EditableZSetCell(
                        row: row,
                        editingMember: $editingMember,
                        editScore: $editScore,
                        rowValue: "\(row.score)\t\(row.member)",
                        onSaveMember: onSaveMember
                    )
                }
                .width(100)

                TableColumn("Member") { row in
                    Text(row.member)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                        .copyableCell(row.member, row: "\(row.score)\t\(row.member)")
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

                if hasMoreRows {
                    Button("Load more") {
                        onLoadMore()
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                StatusFooterView(
                    countText: detailCountText(loaded: rows.count, total: keyLength, noun: "members"),
                    sizeText: keySize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) }
                )
            }
            .padding(AppTheme.spacing)
        }
        .onAppear {
            pendingSearchText = searchText
        }
        .onChange(of: searchText) { _, newValue in
            pendingSearchText = newValue
        }
    }
}

struct EditableZSetCell: View {
    let row: ZSetRow
    @Binding var editingMember: String?
    @Binding var editScore: String
    let rowValue: String
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
                .copyableCell(row.score, row: rowValue)
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
