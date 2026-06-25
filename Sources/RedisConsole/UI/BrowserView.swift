import SwiftUI

struct BrowserView: View {
    @Environment(ConnectionState.self) private var app
    @State private var searchText = ""
    @State private var showingAddKey = false
    @State private var keyPendingDeletion: RedisKeyEntry?
    @State private var newKeyName = ""
    @State private var newKeyType = "string"
    @State private var newKeyValue = ""
    @State private var expandedNamespaces: Set<String> = []
    @State private var keyListScrollTarget: String?
    @State private var productionDeleteKey: RedisKeyEntry?
    @State private var productionConfirmText = ""
    @State private var isAutoRefreshEnabled = false
    @State private var autoRefreshInterval = 5

    private let listScanCount = 500
    private let treeScanCount = 10_000

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 0) {
            // MARK: Header Bar
            HStack(spacing: 8) {
                Picker("", selection: $app.keyTypeFilter) {
                    Text("All Types").tag("")
                    Text("String").tag("string")
                    Text("List").tag("list")
                    Text("Hash").tag("hash")
                    Text("Set").tag("set")
                    Text("Sorted Set").tag("zset")
                }
                .labelsHidden()

                ZStack(alignment: .trailing) {
                    TextField("Filter by key pattern (e.g. user:*)", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            app.keyFilter = searchText.isEmpty ? "*" : searchText
                            app.keyScanCount = currentScanCount
                            Task { await app.scanKeys(reset: true) }
                        }
                    HStack(spacing: 4) {
                        if !searchText.isEmpty {
                            Button("Clear Search", systemImage: "xmark.circle.fill") {
                                searchText = ""
                                app.keyFilter = "*"
                                app.keyScanCount = currentScanCount
                                Task { await app.scanKeys(reset: true) }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            Divider()

            if let error = app.connectionError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error)
                        .lineLimit(2)
                    Spacer()
                    Button("Dismiss", systemImage: "xmark") {
                        app.connectionError = nil
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Dismiss")
                }
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

                Divider()
            }

            PersistentSplitView(
                leftMinWidth: 250,
                rightMinWidth: 250
            ) {
                // MARK: Left Panel
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Picker(
                            "Key List Style",
                            selection: Binding(
                                get: { app.isNamespaceGroupingEnabled },
                                set: { isEnabled in
                                    guard app.isNamespaceGroupingEnabled != isEnabled else { return }
                                    app.isNamespaceGroupingEnabled = isEnabled
                                    app.keyScanCount = isEnabled ? treeScanCount : listScanCount
                                    expandedNamespaces = []
                                    Task { await app.scanKeys(reset: true) }
                                }
                            )
                        ) {
                            Image(systemName: "list.bullet")
                                .help("Flat list")
                                .tag(false)
                            Image(systemName: "folder")
                                .help("Group by namespace")
                                .tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .help("Toggle key list layout")

                        Spacer()

                        KeyRefreshControl(
                            isAutoRefreshEnabled: $isAutoRefreshEnabled,
                            autoRefreshInterval: $autoRefreshInterval,
                            isDisabled: app.isLoadingKeys
                        ) {
                            app.keyScanCount = currentScanCount
                            Task { await app.scanKeys(reset: true) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                    Divider()

                    let displayedKeys = filteredKeys

                    if app.isLoadingKeys && app.keys.isEmpty {
                        Spacer()
                        ProgressView("Scanning keys...")
                        Spacer()
                    } else if app.keys.isEmpty {
                        Spacer()
                        ContentUnavailableView(
                            searchText.isEmpty ? "No keys found" : "No matching keys",
                            systemImage: "key.slash"
                        )
                        loadMoreOrScanningView
                        Spacer()
                    } else if displayedKeys.isEmpty {
                        Spacer()
                        ContentUnavailableView(
                            "No matching keys",
                            systemImage: "key.slash"
                        )
                        loadMoreOrScanningView
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

                        loadMoreOrScanningView
                    }

                    Divider()

                    WorkspaceFooterBar {
                        Button("Add Key", systemImage: "plus") {
                            newKeyName = ""
                            newKeyType = "string"
                            newKeyValue = ""
                            showingAddKey = true
                        }
                        .labelStyle(.iconOnly)
                        .font(.body)
                        .buttonStyle(.borderless)
                        .help("Add key")

                        Spacer()

                        StatusFooterView(
                            countText: browserFooterText(displayedCount: filteredKeys.count)
                        )
                    }
                }
            } right: {
                KeyDetailView()
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
        .confirmationDialog(
            "Delete Key?",
            isPresented: Binding(
                get: { keyPendingDeletion != nil && !isProduction },
                set: { isPresented in
                    if !isPresented { keyPendingDeletion = nil }
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
            Button("Cancel", role: .cancel) { keyPendingDeletion = nil }
        } message: {
            if let key = keyPendingDeletion {
                Text("This permanently deletes \(key.key).")
            }
        }
        .sheet(
            isPresented: Binding(
                get: { keyPendingDeletion != nil && isProduction },
                set: { isPresented in
                    if !isPresented {
                        keyPendingDeletion = nil
                        productionDeleteKey = nil
                        productionConfirmText = ""
                    }
                }
            )
        ) {
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
        .task(id: autoRefreshTaskID) {
            guard isAutoRefreshEnabled else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(autoRefreshInterval))
                guard !Task.isCancelled, !app.isLoadingKeys else { continue }
                app.keyScanCount = currentScanCount
                await app.scanKeys(reset: true)
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var loadMoreOrScanningView: some View {
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

    // MARK: - Helpers

    private var filteredKeys: [RedisKeyEntry] {
        app.keys.filter { app.keyTypeFilter.isEmpty || $0.type == app.keyTypeFilter }
    }

    private var currentScanCount: Int {
        app.isNamespaceGroupingEnabled ? treeScanCount : listScanCount
    }

    private var isProduction: Bool {
        app.selectedConnection?.environment == .production
    }

    private var autoRefreshTaskID: String {
        "\(isAutoRefreshEnabled)|\(autoRefreshInterval)"
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
