import SwiftUI

// MARK: - List Insert Position

enum ListInsertPosition {
    case head, tail
}

struct KeyDetailView: View {
    @Environment(TabState.self) private var tab
    @State private var didCopyKey = false
    @State private var editingString = false
    @State private var stringValue = ""
    @State private var showingAddHashField = false
    @State private var newHashField = ""
    @State private var newHashValue = ""
    @State private var showingAddListElement = false
    @State private var newListElement = ""
    @State private var newListInsertPosition: ListInsertPosition = .head
    @State private var showingAddSetMember = false
    @State private var newSetMember = ""
    @State private var showingAddZSetMember = false
    @State private var newZSetMember = ""
    @State private var newZSetScore = ""
    @State private var keyPendingDeletion: RedisKeyEntry?
    @State private var showingTTLEditor = false
    @State private var ttlInput = ""
    @State private var ttlEditorError: String?
    @State private var autoRefreshInterval: TimeInterval = 0
    @State private var productionConfirmText = ""
    @State private var deleteFeedbackTrigger = false
    @State private var ttlFeedbackTrigger = false

    private let maxTTL = 2_147_483_647

    // MARK: - Body
    var body: some View {
        @Bindable var tab = tab

        VStack(spacing: 0) {
            if let key = tab.selectedKey {
                headerView(key: key)

                Divider()

                if let error = tab.keyDetailError {
                    ErrorBanner(message: error, dismissAction: { tab.keyDetailError = nil })
                    Divider()
                }

                if tab.isLoadingDetail {
                    Spacer()
                    LoadingState(message: "Loading value...")
                    Spacer()
                } else {
                    detailContent(key: key)
                }
            } else {
                Spacer()
                ContentUnavailableView(
                    "Select a key to view its value",
                    systemImage: "sidebar.left",
                    description: Text("Choose a key from the list on the left")
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
                    Task { await tab.deleteKey(key) }
                    keyPendingDeletion = nil
                    deleteFeedbackTrigger.toggle()
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
                        Task { await tab.deleteKey(key) }
                        keyPendingDeletion = nil
                        productionConfirmText = ""
                        deleteFeedbackTrigger.toggle()
                    },
                    onCancel: {
                        keyPendingDeletion = nil
                        productionConfirmText = ""
                    }
                )
                .presentationSizing(.form)
            }
        }
        .onChange(of: tab.selectedKey?.key) {
            showingTTLEditor = false
            ttlEditorError = nil
        }
        .sensoryFeedback(.success, trigger: deleteFeedbackTrigger)
        .sensoryFeedback(.success, trigger: ttlFeedbackTrigger)
        .task(id: autoRefreshTaskID) {
            guard autoRefreshInterval > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(autoRefreshInterval))
                guard !Task.isCancelled, tab.selectedKey != nil, !tab.isLoadingDetail else { continue }
                await tab.refreshSelectedKey()
            }
        }
    }

    private var autoRefreshTaskID: String {
        "\(tab.selectedKey?.key ?? "")|\(autoRefreshInterval)"
    }

    private var isProduction: Bool {
        tab.selectedConnection?.environment == .production
    }

    // MARK: - Detail Content
    @ViewBuilder
    private func detailContent(key: RedisKeyEntry) -> some View {
        @Bindable var tab = tab

        switch tab.keyType {
        case "string":
            StringDetailView(
                key: key.key,
                value: tab.keyDetail,
                format: $tab.stringValueFormat,
                onSave: { value in
                    Task {
                        await tab.updateStringValue(key: key.key, value: value)
                        await tab.refreshSelectedKey()
                    }
                }
            )

        case "hash":
            HashDetailView(
                key: key.key,
                rows: tab.keyDetailRows,
                totalCount: tab.keyDetailTotalCount ?? key.length,
                searchText: tab.keyDetailSearchText,
                hasMoreRows: tab.keyDetailHasMoreRows,
                isProduction: isProduction,
                onSearch: { text in
                    Task { await tab.searchSelectedKeyDetail(text) }
                },
                onLoadMore: {
                    Task { await tab.loadMoreSelectedKeyDetailRows() }
                },
                onAddField: { showingAddHashField = true },
                onSaveField: { field, value in
                    Task {
                        await tab.updateHashField(key: key.key, field: field, value: value)
                        await tab.refreshSelectedKey()
                    }
                },
                onDeleteField: { field in
                    Task {
                        await tab.deleteHashField(key: key.key, field: field)
                        await tab.refreshSelectedKey()
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
                            await tab.addHashField(key: key.key, field: field, value: value)
                            await tab.refreshSelectedKey()
                        }
                        showingAddHashField = false
                    },
                    onCancel: { showingAddHashField = false }
                )
                .presentationSizing(.form)
            }

        case "list":
            ListDetailView(
                key: key.key,
                rows: tab.keyDetailRows,
                totalCount: tab.keyDetailTotalCount ?? key.length,
                hasMoreRows: tab.keyDetailHasMoreRows,
                isProduction: isProduction,
                onLoadMore: {
                    Task { await tab.loadMoreSelectedKeyDetailRows() }
                },
                onAddElement: { showingAddListElement = true },
                onSaveElement: { index, value in
                    Task {
                        await tab.updateListElement(key: key.key, index: index, value: value)
                        await tab.refreshSelectedKey()
                    }
                },
                onDeleteElement: { index, _ in
                    Task {
                        await tab.deleteListElement(key: key.key, index: index)
                        await tab.refreshSelectedKey()
                    }
                }
            )
            .sheet(isPresented: $showingAddListElement) {
                AddListElementSheet(
                    key: key.key,
                    value: $newListElement,
                    position: $newListInsertPosition,
                    onSave: { value, position in
                        Task {
                            await tab.addListElement(key: key.key, value: value, tail: position == .tail)
                            await tab.refreshSelectedKey()
                        }
                        showingAddListElement = false
                    },
                    onCancel: { showingAddListElement = false }
                )
                .presentationSizing(.form)
            }

        case "set":
            SetDetailView(
                key: key.key,
                rows: tab.keyDetailRows,
                totalCount: tab.keyDetailTotalCount ?? key.length,
                searchText: tab.keyDetailSearchText,
                hasMoreRows: tab.keyDetailHasMoreRows,
                isProduction: isProduction,
                onSearch: { text in
                    Task { await tab.searchSelectedKeyDetail(text) }
                },
                onLoadMore: {
                    Task { await tab.loadMoreSelectedKeyDetailRows() }
                },
                onAddMember: { showingAddSetMember = true },
                onDeleteMember: { member in
                    Task {
                        await tab.deleteSetMember(key: key.key, member: member)
                        await tab.refreshSelectedKey()
                    }
                }
            )
            .sheet(isPresented: $showingAddSetMember) {
                AddSetMemberSheet(
                    key: key.key,
                    member: $newSetMember,
                    onSave: { member in
                        Task {
                            await tab.addSetMember(key: key.key, member: member)
                            await tab.refreshSelectedKey()
                        }
                        showingAddSetMember = false
                    },
                    onCancel: { showingAddSetMember = false }
                )
                .presentationSizing(.form)
            }

        case "zset":
            ZSetDetailView(
                key: key.key,
                rows: tab.keyDetailRows,
                totalCount: tab.keyDetailTotalCount ?? key.length,
                searchText: tab.keyDetailSearchText,
                order: tab.keyDetailZSetOrder,
                hasMoreRows: tab.keyDetailHasMoreRows,
                isProduction: isProduction,
                onSearch: { text in
                    Task { await tab.searchSelectedKeyDetail(text) }
                },
                onOrderChange: { order in
                    Task { await tab.updateSelectedZSetOrder(order) }
                },
                onLoadMore: {
                    Task { await tab.loadMoreSelectedKeyDetailRows() }
                },
                onAddMember: { showingAddZSetMember = true },
                onSaveMember: { member, score in
                    Task {
                        await tab.updateZSetScore(key: key.key, member: member, score: score)
                        await tab.refreshSelectedKey()
                    }
                },
                onDeleteMember: { member in
                    Task {
                        await tab.deleteZSetMember(key: key.key, member: member)
                        await tab.refreshSelectedKey()
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
                            await tab.addZSetMember(key: key.key, member: member, score: score)
                            await tab.refreshSelectedKey()
                        }
                        showingAddZSetMember = false
                    },
                    onCancel: { showingAddZSetMember = false }
                )
                .presentationSizing(.form)
            }

        default:
            if tab.keyDetailRows.isEmpty {
                emptyValueView
            } else {
                genericRowsView
            }
        }
    }

    // MARK: - Header
    private func headerView(key: RedisKeyEntry) -> some View {
        HStack(spacing: AppSpacing.small) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                    Badge(text: key.type, isLoading: key.type.isEmpty)
                    Text(key.key)
                        .font(.title3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }

                HStack(spacing: AppSpacing.medium - AppSpacing.xxSmall) {
                    if let totalCount = tab.keyDetailTotalCount ?? key.length {
                        HStack(spacing: AppSpacing.xxSmall) {
                            Image(systemName: "number")
                            Text("Length: \(totalCount)")
                        }
                        .foregroundStyle(.secondary)
                    }
                    if let size = tab.valueSize ?? key.size {
                        HStack(spacing: AppSpacing.xxSmall) {
                            Image(systemName: "memorychip")
                            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .memory))
                        }
                        .foregroundStyle(.secondary)
                    }
                    Button {
                        beginEditingTTL(for: key)
                    } label: {
                        HStack(spacing: AppSpacing.xxSmall) {
                            Image(systemName: "clock")
                            Text("TTL: \(key.ttlText)")
                            Image(systemName: "pencil")
                                .imageScale(.small)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(key.hasExpiry ? AppColor.warning : .secondary)
                    .disabled(tab.isLoadingDetail)
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
                    if let refreshedAt = tab.keyDetailLastRefreshedAt {
                        HStack(spacing: AppSpacing.xxSmall) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text(refreshedAt, style: .time)
                        }
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: AppSpacing.small) {
                RefreshControl(
                    autoRefreshInterval: $autoRefreshInterval,
                    isLoading: tab.isLoadingDetail,
                    intervals: [5, 10, 15, 30, 60]
                ) {
                    Task { await tab.refreshSelectedKey() }
                }

                Button("Copy Key", systemImage: didCopyKey ? "checkmark" : "doc.on.doc") {
                    copyToPasteboard(key.key)
                    didCopyKey = true
                    Task {
                        try? await Task.sleep(for: .milliseconds(1500))
                        didCopyKey = false
                    }
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(didCopyKey ? AppColor.success : .primary)
                .buttonStyle(.borderless)
                .disabled(tab.isLoadingDetail)
                .help("Copy key")

                Button("Delete Key", systemImage: "trash", role: .destructive) {
                    keyPendingDeletion = key
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(tab.isLoadingDetail)
                .help("Delete key")
            }
        }
        .padding(AppSpacing.small)
    }

    // MARK: - TTL Editing
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
            let previousError = tab.keyDetailError
            await tab.updateKeyTTL(key, ttl: ttl)
            // Only fire success feedback when the operation didn't set a new error.
            if tab.keyDetailError == previousError {
                ttlFeedbackTrigger.toggle()
            }
        }
    }

    private func validatedTTLInput(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        guard let ttl = Int(digits) else {
            return digits
        }
        return min(ttl, maxTTL).description
    }

    // MARK: - Generic Views
    private var genericRowsView: some View {
        List {
            Section {
                ForEach(Array(tab.keyDetailRows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top) {
                        Text(row.0)
                            .font(AppFont.monoSubheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 100, alignment: .leading)
                            .copyableCell(row.0, row: "\(row.0)\t\(row.1)")
                        Text(row.1)
                            .font(AppFont.dataCell)
                            .textSelection(.enabled)
                            .copyableCell(row.1, row: "\(row.0)\t\(row.1)")
                    }
                }
            } header: {
                HStack {
                    Text(tab.keyType == "zset" ? "Score" : "Key")
                        .frame(width: 100, alignment: .leading)
                    Text("Value")
                    Spacer()
                }
                .font(.subheadline)
            }
        }
        .listStyle(.inset)
    }

    private var emptyValueView: some View {
        ScrollView {
            Text(tab.keyDetail)
                .font(AppFont.dataCell)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.large)
        }
    }
}

// MARK: - TTL Editor Popover
private struct KeyTTLEditorPopover: View {
    let keyName: String
    @Binding var ttlInput: String
    let error: String?
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text(keyName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: AppSpacing.small) {
                Text("TTL")
                    .font(.headline)
                TextField("No limit", text: $ttlInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .onSubmit(onSave)
                Text("s")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let error {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.error)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppSpacing.large)
        .frame(width: AppSize.ttlEditorWidth)
    }
}
