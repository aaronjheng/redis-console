import SwiftUI

// MARK: - Hash Detail View

struct HashRow: Identifiable {
    let id = UUID()
    let field: String
    let value: String
}

struct HashDetailView: View {
    let key: String
    let rows: [(String, String)]
    let keyLength: Int?
    let searchText: String
    let hasMoreRows: Bool
    let onSearch: (String) -> Void
    let onLoadMore: () -> Void
    let onAddField: () -> Void
    let onSaveField: (String, String) -> Void
    let onDeleteField: (String) -> Void

    @State private var editingField: String?
    @State private var editValue = ""
    @State private var pendingSearchText = ""

    private var hashRows: [HashRow] {
        rows.map { HashRow(field: $0.0, value: $0.1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailSearchField(
                searchText: $pendingSearchText,
                placeholder: "Field filter",
                onSearch: { onSearch(pendingSearchText) }
            )
            .padding(AppTheme.spacing)

            Divider()

            Table(hashRows) {
                TableColumn("Field") { row in
                    Text(row.field)
                        .font(.system(.body, design: .monospaced))
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
                    HStack(spacing: AppTheme.spacing) {
                        Button("Edit Field", systemImage: "pencil") {
                            editingField = row.field
                            editValue = row.value
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Edit field")

                        DeleteIconButton(
                            action: { onDeleteField(row.field) },
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
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)
                .copyableCell(row.value, row: rowValue)
                .onTapGesture(count: 2) {
                    editingField = row.field
                    editValue = row.value
                }
        }
    }
}
