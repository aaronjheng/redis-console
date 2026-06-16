import SwiftUI

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
    @State private var keyListScrollTarget: String?
    @State private var productionDeleteKey: RedisKeyEntry?
    @State private var productionBulkDelete: BulkDeletePreview?
    @State private var productionConfirmText = ""

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
                                scrollTargetKey: keyListScrollTarget,
                                onDeleteKey: { keyPendingDeletion = $0 },
                                onCopyKey: copyKeyToPasteboard
                            )
                        } else {
                            KeyFlatList(
                                keys: displayedKeys,
                                selectedKey: $app.selectedKey,
                                scrollTargetKey: keyListScrollTarget,
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

                WorkspaceFooterBar {
                    Button {
                        newKeyName = ""
                        newKeyType = "string"
                        newKeyValue = ""
                        showingAddKey = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .font(.body)
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
                    .font(.body)
                    .buttonStyle(.borderless)
                    .disabled(isPreparingBulkDelete || isDeletingBulkKeys || app.keys.isEmpty)
                    .help("Bulk delete current filter")

                    Spacer()

                    StatusFooterView(
                        countText: browserFooterText(displayedCount: displayedKeys.count)
                    )
                }
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
                get: { bulkDeletePreview != nil && !isProduction },
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
        .sheet(isPresented: Binding(
            get: { bulkDeletePreview != nil && isProduction },
            set: { isPresented in
                if !isPresented {
                    bulkDeletePreview = nil
                    productionBulkDelete = nil
                    productionConfirmText = ""
                }
            }
        )) {
            if let preview = bulkDeletePreview ?? productionBulkDelete {
                ProductionConfirmView(
                    title: "Delete \(preview.keys.count) Keys?",
                    message: bulkDeletePreviewMessage(preview),
                    confirmText: "DELETE",
                    input: $productionConfirmText,
                    onConfirm: {
                        Task { await executeBulkDelete(preview) }
                        bulkDeletePreview = nil
                        productionBulkDelete = nil
                        productionConfirmText = ""
                    },
                    onCancel: {
                        bulkDeletePreview = nil
                        productionBulkDelete = nil
                        productionConfirmText = ""
                    }
                )
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
            if let result = bulkDeleteResult, !result.deletedKeys.isEmpty {
                Button("Export Deleted Keys") {
                    exportDeletedKeys(result.deletedKeys)
                    bulkDeleteResult = nil
                }
            }
            Button("OK") {
                bulkDeleteResult = nil
            }
        } message: {
            if let result = bulkDeleteResult {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bulkDeleteResultMessage(result))
                    if !result.deletedKeys.isEmpty {
                        Text("\(result.deletedKeys.count) keys were deleted.")
                            .font(.caption)
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete Key?",
            isPresented: Binding(
                get: { keyPendingDeletion != nil && !isProduction },
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
        .sheet(isPresented: Binding(
            get: { keyPendingDeletion != nil && isProduction },
            set: { isPresented in
                if !isPresented {
                    keyPendingDeletion = nil
                    productionDeleteKey = nil
                    productionConfirmText = ""
                }
            }
        )) {
            if let key = productionDeleteKey ?? keyPendingDeletion {
                ProductionConfirmView(
                    title: "Delete Key?",
                    message: "This permanently deletes \(key.key).",
                    confirmText: "DELETE",
                    input: $productionConfirmText,
                    onConfirm: {
                        Task { await app.deleteKey(key) }
                        keyPendingDeletion = nil
                        productionDeleteKey = nil
                        productionConfirmText = ""
                    },
                    onCancel: {
                        keyPendingDeletion = nil
                        productionDeleteKey = nil
                        productionConfirmText = ""
                    }
                )
            }
        }
        .onAppear {
            app.keyScanCount = currentScanCount
            searchText = app.keyFilter == "*" ? "" : app.keyFilter
        }
        .overlay {
            if isDeletingBulkKeys && app.bulkDeleteProgress > 0 && app.bulkDeleteProgress < 1.0 {
                ProgressOverlayView(
                    progress: app.bulkDeleteProgress,
                    text: app.bulkDeleteProgressText
                )
            }
        }
    }

    private var filteredKeys: [RedisKeyEntry] {
        app.keys.filter { app.keyTypeFilter.isEmpty || $0.type == app.keyTypeFilter }
    }

    private var currentScanCount: Int {
        app.isNamespaceGroupingEnabled ? treeScanCount : listScanCount
    }

    private var isProduction: Bool {
        app.selectedConnection?.environment == .production
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
        let totalText = app.keyTotalCount.map(String.init) ?? "-"
        let limitText = app.keyScanLimitReached ? " · Threshold Reached" : ""
        let countText = "\(app.keys.count) Loaded · \(displayedCount) Shown\(limitText)"
        let showsScanProgress = app.keyFilter != "*" || !app.keyTypeFilter.isEmpty || app.isNamespaceGroupingEnabled

        if showsScanProgress {
            return "Results \(displayedCount) · Scanned \(app.keyScannedCount) / \(totalText) · \(countText)"
        }
        return "Total \(totalText) · \(countText)"
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
            let createdKey = app.insertCreatedKeyIntoBrowser(name: name, type: type)
            let isCreatedKeyVisible = app.keyTypeFilter.isEmpty || app.keyTypeFilter == type
            if let createdKey, isCreatedKeyVisible {
                app.selectedKey = createdKey
                keyListScrollTarget = createdKey.key
            }
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

    private func exportDeletedKeys(_ keys: [String]) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "deleted-keys-\(formatter.string(from: Date())).txt"

        let panel = NSSavePanel()
        panel.title = "Export Deleted Keys"
        panel.nameFieldStringValue = filename
        panel.message = "Save the list of deleted keys"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let content = keys.joined(separator: "\n")
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
}

private func scrollToKey(_ key: String?, using proxy: ScrollViewProxy) {
    guard let key else { return }
    proxy.scrollTo(key, anchor: .top)
}

private struct KeyFlatList: View {
    let keys: [RedisKeyEntry]
    @Binding var selectedKey: RedisKeyEntry?
    let scrollTargetKey: String?
    let onDeleteKey: (RedisKeyEntry) -> Void
    let onCopyKey: (RedisKeyEntry) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedKey) {
                ForEach(keys) { entry in
                    KeyRow(entry: entry)
                        .id(entry.key)
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
            .onAppear {
                scrollToKey(scrollTargetKey, using: proxy)
            }
            .onChange(of: scrollTargetKey) { _, newValue in
                scrollToKey(newValue, using: proxy)
            }
        }
    }
}

private struct KeyNamespaceList: View {
    let tree: KeyNamespaceTree
    @Binding var selectedKey: RedisKeyEntry?
    @Binding var expandedNamespaces: Set<String>
    let scrollTargetKey: String?
    let onDeleteKey: (RedisKeyEntry) -> Void
    let onCopyKey: (RedisKeyEntry) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedKey) {
                ForEach(tree.rootKeys) { entry in
                    KeyRow(entry: entry)
                        .id(entry.key)
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
                        allKeys: tree.allKeys,
                        selectedKey: $selectedKey,
                        expandedNamespaces: $expandedNamespaces,
                        onDeleteKey: onDeleteKey,
                        onCopyKey: onCopyKey
                    )
                }
            }
            .listStyle(.plain)
            .onAppear {
                scrollToKey(scrollTargetKey, using: proxy)
            }
            .onChange(of: scrollTargetKey) { _, newValue in
                scrollToKey(newValue, using: proxy)
            }
        }
    }
}

private struct KeyNamespaceNodeView: View {
    let namespace: KeyNamespaceNode
    let separator: String
    let allKeys: [RedisKeyEntry]
    @Binding var selectedKey: RedisKeyEntry?
    @Binding var expandedNamespaces: Set<String>
    let onDeleteKey: (RedisKeyEntry) -> Void
    let onCopyKey: (RedisKeyEntry) -> Void

    private let pageSize = 500

    var body: some View {
        DisclosureGroup(isExpanded: namespaceExpansion) {
            ForEach(namespace.children) { childNamespace in
                KeyNamespaceNodeView(
                    namespace: childNamespace,
                    separator: separator,
                    allKeys: allKeys,
                    selectedKey: $selectedKey,
                    expandedNamespaces: $expandedNamespaces,
                    onDeleteKey: onDeleteKey,
                    onCopyKey: onCopyKey
                )
            }

            let namespaceKeys = self.namespaceKeys
            let displayedKeys = Array(namespaceKeys.prefix(pageSize))
            let hasMore = namespaceKeys.count > pageSize

            ForEach(displayedKeys) { entry in
                KeyRow(entry: entry, displayName: KeyNamespaceTree.leafName(for: entry.key, separator: separator))
                    .id(entry.key)
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

            if hasMore {
                HStack {
                    Spacer()
                    Text("\(namespaceKeys.count - pageSize) more keys...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        } label: {
            KeyNamespaceRow(namespace: namespace)
        }
    }

    private var namespaceKeys: [RedisKeyEntry] {
        let prefix = namespace.id.isEmpty ? "" : "\(namespace.id)\(separator)"
        return allKeys.filter { $0.key.hasPrefix(prefix) || $0.key == namespace.id }
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
    let allKeys: [RedisKeyEntry]

    init(entries: [RedisKeyEntry], separator: String) {
        self.separator = KeyNamespaceTree.normalizedSeparator(separator)
        self.allKeys = entries
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

// MARK: - Production Confirmation View

struct ProductionConfirmView: View {
    let title: String
    let message: String
    let confirmText: String
    @Binding var input: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)

            Text(title)
                .font(.title2)
                .bold()

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 0) {
                Image(systemName: "shield")
                    .foregroundStyle(.red)
                Text("This is a PRODUCTION database.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 4) {
                Text("Type \"\(confirmText)\" to confirm:")
                    .font(.caption)
                Spacer()
            }

            TextField("", text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit(confirmIfValid)

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Delete", role: .destructive, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(input != confirmText)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func confirmIfValid() {
        if input == confirmText {
            onConfirm()
        }
    }
}

// MARK: - Progress Overlay View

struct ProgressOverlayView: View {
    let progress: Double
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(width: 200)

                Text(text)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
