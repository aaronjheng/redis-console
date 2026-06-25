import SwiftUI

// MARK: - List Detail View

struct ListRow: Identifiable {
    var id: Int { index }
    let index: Int
    let value: String
}

struct EditableListCell: View {
    let row: ListRow
    @Binding var editingIndex: Int?
    @Binding var editValue: String
    let rowValue: String
    let onSaveElement: (Int, String) -> Void

    var body: some View {
        if editingIndex == row.index {
            InlineTextField(
                text: $editValue,
                onSubmit: { onSaveElement(row.index, editValue) },
                onCancel: { editingIndex = nil }
            )
        } else {
            Text(row.value)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)
                .copyableCell(row.value, row: rowValue)
                .onTapGesture(count: 2) {
                    editingIndex = row.index
                    editValue = row.value
                }
        }
    }
}

struct ListDetailView: View {
    let key: String
    let rows: [(String, String)]
    let keyLength: Int?
    let hasMoreRows: Bool
    let onLoadMore: () -> Void
    let onAddElement: () -> Void
    let onSaveElement: (Int, String) -> Void
    let onDeleteElement: (Int, String) -> Void

    @State private var editingIndex: Int?
    @State private var editValue = ""

    private var listRows: [ListRow] {
        rows.compactMap { row in
            guard let index = Int(row.0) else { return nil }
            return ListRow(index: index, value: row.1)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(listRows) {
                TableColumn("Index") { row in
                    Text("\(row.index)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .copyableCell("\(row.index)", row: "\(row.index)\t\(row.value)")
                }
                .width(60)

                TableColumn("Value") { row in
                    EditableListCell(
                        row: row,
                        editingIndex: $editingIndex,
                        editValue: $editValue,
                        rowValue: "\(row.index)\t\(row.value)",
                        onSaveElement: onSaveElement
                    )
                }

                TableColumn("Actions") { row in
                    HStack(spacing: AppTheme.spacing) {
                        Button("Edit Element", systemImage: "pencil") {
                            editingIndex = row.index
                            editValue = row.value
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Edit element")

                        DeleteIconButton(
                            action: { onDeleteElement(row.index, row.value) },
                            helpText: "Delete element"
                        )
                    }
                }
                .width(80)
            }

            Divider()

            WorkspaceFooterBar {
                Button("Add Element", systemImage: "plus") {
                    onAddElement()
                }
                .labelStyle(.iconOnly)
                .font(.body)
                .buttonStyle(.borderless)
                .help("Add element")

                if hasMoreRows {
                    Button("Load more") {
                        onLoadMore()
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                StatusFooterView(
                    countText: detailCountText(loaded: rows.count, total: keyLength, noun: "elements")
                )
            }
        }
    }
}
