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
    var isProduction: Bool = false
    let onSearch: (String) -> Void
    let onLoadMore: () -> Void
    let onAddMember: () -> Void
    let onDeleteMember: (String) -> Void

    @State private var pendingSearchText = ""
    @State private var memberPendingDeletion: String?
    @State private var productionConfirmText = ""

    private var setRows: [SetRow] {
        rows.map { SetRow(member: $0.0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterField("Member filter", text: $pendingSearchText) {
                onSearch(pendingSearchText)
            }
            .padding(AppSpacing.small)

            Divider()

            Table(setRows) {
                TableColumn("Member") { row in
                    Text(row.member)
                        .font(AppFont.dataCell)
                        .lineLimit(2)
                        .copyableCell(row.member, row: row.member)
                }

                TableColumn("Actions") { row in
                    DeleteIconButton(
                        action: { memberPendingDeletion = row.member },
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
