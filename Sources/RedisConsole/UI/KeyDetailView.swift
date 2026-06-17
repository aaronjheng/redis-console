import SwiftUI

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
    @State private var productionConfirmText = ""

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
        .sheet(
            isPresented: Binding(
                get: { keyPendingDeletion != nil && isProduction },
                set: { isPresented in
                    if !isPresented {
                        keyPendingDeletion = nil
                        productionConfirmText = ""
                    }
                }
            )
        ) {
            if let key = keyPendingDeletion {
                ProductionConfirmView(
                    title: "Delete Key?",
                    message: "This permanently deletes \(key.key).",
                    confirmText: "DELETE",
                    input: $productionConfirmText,
                    onConfirm: {
                        Task { await app.deleteKey(key) }
                        keyPendingDeletion = nil
                        productionConfirmText = ""
                    },
                    onCancel: {
                        keyPendingDeletion = nil
                        productionConfirmText = ""
                    }
                )
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

    private var isProduction: Bool {
        app.selectedConnection?.environment == .production
    }

    @ViewBuilder
    private func detailContent(key: RedisKeyEntry) -> some View {
        switch app.keyType {
        case "string":
            StringDetailView(
                key: key.key,
                value: app.keyDetail,
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
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    KeyTypeBadge(type: key.type)
                    Text(key.key)
                        .font(.title3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 10) {
                    if let length = app.keyDetailLength ?? key.length {
                        HStack(spacing: 2) {
                            Image(systemName: "number")
                            Text("Length: \(length)")
                        }
                        .foregroundStyle(.secondary)
                    }
                    if let size = app.valueSize ?? key.size {
                        HStack(spacing: 2) {
                            Image(systemName: "memorychip")
                            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .memory))
                        }
                        .foregroundStyle(.secondary)
                    }
                    Button {
                        beginEditingTTL(for: key)
                    } label: {
                        HStack(spacing: 2) {
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
                    if let refreshedAt = app.keyDetailLastRefreshedAt {
                        HStack(spacing: 2) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text(refreshedAt, style: .time)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
            Spacer()
            KeyDetailRefreshControl(
                isAutoRefreshEnabled: $isAutoRefreshEnabled,
                autoRefreshInterval: $autoRefreshInterval,
                isDisabled: app.isLoadingDetail
            ) {
                Task { await app.refreshSelectedKey() }
            }

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

private struct KeyDetailRefreshControl: View {
    @Binding var isAutoRefreshEnabled: Bool
    @Binding var autoRefreshInterval: Int
    var isDisabled: Bool
    var onRefresh: () -> Void

    private static let intervals = [5, 10, 15, 30, 60]

    private static func intervalTitle(_ seconds: Int) -> String {
        if seconds.isMultiple(of: 60) {
            return "\(seconds / 60)m"
        }
        return "\(seconds)s"
    }

    @State private var isRefreshHovering = false
    @State private var isMenuHovering = false

    var body: some View {
        HStack(spacing: 0) {
            refreshButton
            separator
            intervalMenu
        }
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .opacity(isDisabled ? 0.5 : 1)
    }

    private var refreshButton: some View {
        Button(action: onRefresh) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
                .background(
                    isRefreshHovering && !isDisabled
                        ? Color.primary.opacity(0.08)
                        : Color.clear
                )
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 6,
                        bottomLeadingRadius: 6,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isRefreshHovering = $0 }
        .help("Refresh")
    }

    private var separator: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 0.5, height: 14)
    }

    private var intervalMenu: some View {
        Menu {
            Button {
                isAutoRefreshEnabled = false
            } label: {
                menuItemLabel(text: "Off", checked: !isAutoRefreshEnabled)
            }
            Divider()
            ForEach(Self.intervals, id: \.self) { interval in
                Button {
                    isAutoRefreshEnabled = true
                    autoRefreshInterval = interval
                } label: {
                    menuItemLabel(
                        text: Self.intervalTitle(interval),
                        checked: isAutoRefreshEnabled && autoRefreshInterval == interval
                    )
                }
            }
        } label: {
            HStack(spacing: 0) {
                if isAutoRefreshEnabled {
                    Text(Self.intervalTitle(autoRefreshInterval))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 6)
                } else {
                    Color.clear.frame(width: 18, height: 22)
                }
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .background(
                isMenuHovering && !isDisabled
                    ? Color.primary.opacity(0.08)
                    : Color.clear
            )
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 6,
                    topTrailingRadius: 6,
                    style: .continuous
                )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .disabled(isDisabled)
        .onHover { isMenuHovering = $0 }
        .help(isAutoRefreshEnabled ? "Auto refresh every \(Self.intervalTitle(autoRefreshInterval))" : "Auto refresh off")
    }

    private func menuItemLabel(text: String, checked: Bool) -> some View {
        Text(checked ? "\(text)  ✓" : text)
    }
}
