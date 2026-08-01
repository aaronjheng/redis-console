import SwiftUI

// MARK: - Hash Detail View

struct HashRow: Identifiable {
    var id: String { field }
    let field: String
    let value: String
}

struct HashDetailView: View {
    let key: String
    let rows: [(String, String)]
    let keyLength: Int?
    let searchText: String
    let hasMoreRows: Bool
    var isProduction: Bool = false
    let onSearch: (String) -> Void
    let onLoadMore: () -> Void
    let onAddField: () -> Void
    let onSaveField: (String, String) -> Void
    let onDeleteField: (String) -> Void

    @State private var editingField: String?
    @State private var editValue = ""
    @State private var pendingSearchText = ""
    @State private var fieldPendingDeletion: String?
    @State private var productionConfirmText = ""

    private var hashRows: [HashRow] {
        rows.map { HashRow(field: $0.0, value: $0.1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterField("Field filter", text: $pendingSearchText) {
                onSearch(pendingSearchText)
            }
            .padding(AppSpacing.small)

            Divider()

            Table(hashRows) {
                TableColumn("Field") { row in
                    Text(row.field)
                        .font(AppFont.dataCell)
                        .lineLimit(2)
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
                    HStack(spacing: AppSpacing.small) {
                        Button("Edit Field", systemImage: "pencil") {
                            editingField = row.field
                            editValue = row.value
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Edit field")

                        DeleteIconButton(
                            action: { fieldPendingDeletion = row.field },
                            helpText: "Delete field"
                        )
                    }
                }
                .width(80)
            }

            Divider()

            WorkspaceFooterBar {
                Button("Add Field", systemImage: "plus") {
                    onAddField()
                }
                .labelStyle(.iconOnly)
                .font(.body)
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
                    countText: detailCountText(loaded: rows.count, total: keyLength, noun: "fields")
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
            "Delete Field?",
            isPresented: Binding(
                get: { fieldPendingDeletion != nil && !isProduction },
                set: { if !$0 { fieldPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let field = fieldPendingDeletion {
                Button("Delete \"\(field)\"", role: .destructive) {
                    onDeleteField(field)
                    fieldPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let field = fieldPendingDeletion {
                Text("This permanently deletes field \"\(field)\" from \"\(key)\".")
            }
        }
        .sheet(
            isPresented: Binding(
                get: { fieldPendingDeletion != nil && isProduction },
                set: {
                    if !$0 {
                        fieldPendingDeletion = nil
                        productionConfirmText = ""
                    }
                }
            )
        ) {
            if let field = fieldPendingDeletion {
                ProductionConfirmView(
                    title: "Delete Field?",
                    message: "This permanently deletes field \"\(field)\" from \"\(key)\".",
                    confirmText: "DELETE",
                    input: $productionConfirmText,
                    onConfirm: {
                        onDeleteField(field)
                        fieldPendingDeletion = nil
                        productionConfirmText = ""
                    },
                    onCancel: {
                        fieldPendingDeletion = nil
                        productionConfirmText = ""
                    }
                )
                .presentationSizing(.form)
            }
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
                .font(AppFont.dataCell)
                .lineLimit(2)
                .copyableCell(row.value, row: rowValue)
                .onTapGesture(count: 2) {
                    editingField = row.field
                    editValue = row.value
                }
        }
    }
}
