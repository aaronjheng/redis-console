import AppKit
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

    /// Header metrics of the fixed Score column, matching NSTableView's
    /// default macOS layout: 10pt leading inset before the first column, a
    /// 100pt column plus its intercell gap (the next column starts at 125pt),
    /// and a 28pt header.
    private static let scoreHeaderExtent: CGFloat = 125
    private static let headerHeight: CGFloat = 28
    private static let indicatorTrailingInset: CGFloat = 8

    private static func sortIndicatorImage(for order: KeyDetailZSetOrder) -> NSImage {
        let name: NSImage.Name = order == .ascending ? "NSAscendingSortIndicator" : "NSDescendingSortIndicator"
        return NSImage(named: name) ?? NSImage(size: NSSize(width: 8, height: 8))
    }

    /// Sequel Ace-style header sort control. The Score column is deliberately
    /// left non-sortable because macOS 26 draws an extra separator in front of
    /// the active sort column, so the standard indicator and the click handling
    /// live in this overlay instead.
    private var scoreHeaderSortControl: some View {
        Button {
            onOrderChange(order == .ascending ? .descending : .ascending)
        } label: {
            Color.clear
                .frame(width: Self.scoreHeaderExtent, height: Self.headerHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Image(nsImage: Self.sortIndicatorImage(for: order))
                .foregroundStyle(.secondary)
                .opacity(pendingSearchText.isEmpty ? 1 : 0.35)
                .padding(.trailing, Self.indicatorTrailingInset)
        }
        .disabled(!pendingSearchText.isEmpty)
        .help(pendingSearchText.isEmpty ? "Sort by score" : "Sort order unavailable while filtering")
        .accessibilityLabel("Sort by score")
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterField("Member filter", text: $pendingSearchText) {
                onSearch(pendingSearchText)
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
                        Button("Edit Score", systemImage: "square.and.pencil") {
                            editingMember = row.member
                            editScore = row.score
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(IconButtonStyle(size: .row, weight: .semibold))
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
            .overlay(alignment: .topLeading) {
                scoreHeaderSortControl
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
            "Delete Member",
            isPresented: Binding(
                get: { memberPendingDeletion != nil && !isProduction },
                set: { if !$0 { memberPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let member = memberPendingDeletion {
                Button("Delete", role: .destructive) {
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
                    title: "Delete Member",
                    message: "This permanently deletes member \"\(member)\" from \"\(key)\".",
                    confirmText: "DELETE",
                    confirmButtonTitle: "Delete",
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
