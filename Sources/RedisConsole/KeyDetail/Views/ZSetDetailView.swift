import SwiftUI

// MARK: - ZSet Detail View

struct ZSetEntry: Identifiable {
    var id: String { member }
    let score: String
    let member: String
}

struct ZSetDetailView: View {
    let key: String
    let rows: [(String, String)]
    let totalCount: Int?
    let searchText: String
    let order: KeyDetailZSetOrder
    let hasMoreRows: Bool
    var isProduction: Bool = false
    let onSearch: (String) -> Void
    let onOrderChange: (KeyDetailZSetOrder) -> Void
    let onLoadMore: () -> Void
    let onAddMember: () -> Void
    let onSaveMember: (String, String) -> Void
    let onDeleteMember: (String) -> Void

    @State private var editingMember: String?
    @State private var editScore = ""
    @State private var pendingSearchText = ""
    @State private var memberPendingDeletion: String?
    @State private var productionConfirmText = ""

    private var zsetEntries: [ZSetEntry] {
        rows.map { ZSetEntry(score: $0.0, member: $0.1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.small) {
                FilterField("Member filter", text: $pendingSearchText) {
                    onSearch(pendingSearchText)
                }

                BinaryTogglePicker(
                    selection: Binding(
                        get: { order },
                        set: { onOrderChange($0) }
                    ),
                    first: .ascending,
                    second: .descending,
                    firstLabel: { Text(KeyDetailZSetOrder.ascending.title) },
                    secondLabel: { Text(KeyDetailZSetOrder.descending.title) }
                )
                .frame(width: 180)
                .disabled(!pendingSearchText.isEmpty)
                .help(pendingSearchText.isEmpty ? "Sort order" : "Sort order unavailable while filtering")
            }
            .padding(AppSpacing.small)

            if !pendingSearchText.isEmpty {
                Text("Clear the filter to change the sort order.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.small)
                    .padding(.bottom, AppSpacing.xxSmall)
            }

            Divider()

            Table(zsetEntries) {
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
                        .font(AppFont.dataCell)
                        .lineLimit(2)
                        .copyableCell(row.member, row: "\(row.score)\t\(row.member)")
                }

                TableColumn("Actions") { row in
                    HStack(spacing: AppSpacing.small) {
                        Button("Edit Score", systemImage: "pencil") {
                            editingMember = row.member
                            editScore = row.score
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(IconButtonStyle(size: .row))
                        .help("Edit score")

                        DeleteIconButton(
                            action: { memberPendingDeletion = row.member },
                            helpText: "Delete member",
                            size: .row
                        )
                    }
                }
                .width(80)
            }

            Divider()

            PanelFooterBar {
                Button("Add Member", systemImage: "plus") {
                    onAddMember()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(IconButtonStyle())
                .help("Add member")

                if hasMoreRows {
                    Button("Load More") {
                        onLoadMore()
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                StatusFooterView(
                    countText: detailCountText(loaded: rows.count, total: totalCount, noun: "members")
                )
            }
        }
        .onAppear {
            pendingSearchText = searchText
        }
        .onChange(of: searchText) { _, newValue in
            pendingSearchText = newValue
        }
        .confirmationDialog(
            "Delete Member?",
            isPresented: Binding(
                get: { memberPendingDeletion != nil && !isProduction },
                set: { if !$0 { memberPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let member = memberPendingDeletion {
                Button("Delete \"\(member)\"", role: .destructive) {
                    onDeleteMember(member)
                    memberPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let member = memberPendingDeletion {
                Text("This permanently deletes member \"\(member)\" from \"\(key)\".")
            }
        }
        .sheet(
            isPresented: Binding(
                get: { memberPendingDeletion != nil && isProduction },
                set: {
                    if !$0 {
                        memberPendingDeletion = nil
                        productionConfirmText = ""
                    }
                }
            )
        ) {
            if let member = memberPendingDeletion {
                ProductionConfirmView(
                    title: "Delete Member?",
                    message: "This permanently deletes member \"\(member)\" from \"\(key)\".",
                    confirmText: "DELETE",
                    confirmButtonTitle: "Delete \"\(member)\"",
                    input: $productionConfirmText,
                    onConfirm: {
                        onDeleteMember(member)
                        memberPendingDeletion = nil
                        productionConfirmText = ""
                    },
                    onCancel: {
                        memberPendingDeletion = nil
                        productionConfirmText = ""
                    }
                )
                .presentationSizing(.form)
            }
        }
    }
}

struct EditableZSetCell: View {
    let row: ZSetEntry
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
                .font(AppFont.dataCell)
                .lineLimit(1)
                .copyableCell(row.score, row: rowValue)
                .help("Double-click to edit")
                .onTapGesture(count: 2) {
                    editingMember = row.member
                    editScore = row.score
                }
        }
    }
}
