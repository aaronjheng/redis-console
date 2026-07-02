import SwiftUI

// MARK: - ZSet Detail View

struct ZSetRow: Identifiable {
    var id: String { member }
    let score: String
    let member: String
}

struct ZSetDetailView: View {
    let key: String
    let rows: [(String, String)]
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
            HStack(spacing: AppTheme.spacing) {
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
                        Button("Edit Score", systemImage: "pencil") {
                            editingMember = row.member
                            editScore = row.score
                        }
                        .labelStyle(.iconOnly)
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

            WorkspaceFooterBar {
                Button("Add Member", systemImage: "plus") {
                    onAddMember()
                }
                .labelStyle(.iconOnly)
                .font(.body)
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
                    countText: detailCountText(loaded: rows.count, total: keyLength, noun: "members")
                )
            }
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
