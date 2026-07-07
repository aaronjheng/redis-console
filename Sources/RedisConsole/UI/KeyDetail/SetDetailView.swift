import SwiftUI

// MARK: - Set Detail View

struct SetRow: Identifiable {
    var id: String { member }
    let member: String
}

struct SetDetailView: View {
    let key: String
    let rows: [(String, String)]
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
            .padding(8)

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
