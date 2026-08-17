import SwiftUI

// MARK: - Edit Sheets

struct AddHashFieldSheet: View {
    let key: String
    @Binding var field: String
    @Binding var value: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.large) {
            Text("Add Hash Field")
                .font(.headline)

            Form {
                TextField("Field name", text: $field)
                TextField("Value", text: $value, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { onSave(field, value) }
                    .disabled(field.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppSpacing.large)
    }
}

struct AddListElementSheet: View {
    let key: String
    @Binding var value: String
    @Binding var position: KeyDetailView.ListPosition
    let onSave: (String, KeyDetailView.ListPosition) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.large) {
            Text("Add List Element")
                .font(.headline)

            Form {
                TextField("Value", text: $value, axis: .vertical)
                    .lineLimit(3...6)
                Picker("Position", selection: $position) {
                    Text("Head (LPUSH)").tag(KeyDetailView.ListPosition.head)
                    Text("Tail (RPUSH)").tag(KeyDetailView.ListPosition.tail)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { onSave(value, position) }
                    .disabled(value.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppSpacing.large)
    }
}

struct AddSetMemberSheet: View {
    let key: String
    @Binding var member: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.large) {
            Text("Add Set Member")
                .font(.headline)

            Form {
                TextField("Member value", text: $member, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { onSave(member) }
                    .disabled(member.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppSpacing.large)
    }
}

struct AddZSetMemberSheet: View {
    let key: String
    @Binding var member: String
    @Binding var score: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.large) {
            Text("Add Sorted Set Member")
                .font(.headline)

            Form {
                TextField("Member", text: $member)
                TextField("Score", text: $score)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { onSave(member, score) }
                    .disabled(member.isEmpty || score.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppSpacing.large)
    }
}

// MARK: - Editable Identifiers

extension KeyDetailView.ListPosition: Identifiable {
    var id: Int {
        switch self {
        case .head: return 0
        case .tail: return 1
        }
    }
}

struct AddKeySheet: View {
    @Binding var keyName: String
    @Binding var keyType: String
    @Binding var keyValue: String
    let onSave: (String, String, String) -> Void
    let onCancel: () -> Void

    @State private var listValues: [String] = [""]
    @State private var hashPairs: [(field: String, value: String)] = [("", "")]
    @State private var setMembers: [String] = [""]
    @State private var zsetPairs: [(score: String, member: String)] = [("", "")]

    private static let typeOptions = ["string", "list", "hash", "set", "zset"]

    private var hasValidMembers: Bool {
        switch keyType {
        case "list":
            return listValues.contains { !$0.isEmpty }
        case "hash":
            return hashPairs.contains { !$0.field.isEmpty && !$0.value.isEmpty }
        case "set":
            return setMembers.contains { !$0.isEmpty }
        case "zset":
            return zsetPairs.contains { !$0.score.isEmpty && !$0.member.isEmpty }
        default:
            return true
        }
    }

    private func resetArrays(for type: String) {
        switch type {
        case "list": listValues = [""]
        case "hash": hashPairs = [("", "")]
        case "set": setMembers = [""]
        case "zset": zsetPairs = [("", "")]
        default: break
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            formSection
        }
        .frame(width: 560)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "plus.circle")
                .foregroundStyle(.tint)
            Text("Add New Key")
                .font(.headline)
            Spacer()
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .keyboardShortcut(.cancelAction)
            .help("Close (Esc)")
        }
        .padding(AppSpacing.large)
    }

    // MARK: Form

    private var formSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            keyRow
            typeRow
            valueSection

            HStack(spacing: AppSpacing.small) {
                Spacer()
                Button {
                    save()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(keyName.isEmpty || !hasValidMembers)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, AppSpacing.small)
        }
        .padding(AppSpacing.large)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var keyRow: some View {
        HStack(spacing: AppSpacing.medium) {
            Text("Key")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: AppSize.formLabelWidthCompact, alignment: .leading)
            TextField("Key name", text: $keyName)
                .textFieldStyle(.roundedBorder)
                .font(AppFont.monoSubheadline)
        }
    }

    private var typeRow: some View {
        HStack(spacing: AppSpacing.medium) {
            Text("Type")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: AppSize.formLabelWidthCompact, alignment: .leading)
            OptionsPicker(
                "Select key type",
                selection: $keyType,
                options: Self.typeOptions,
                label: { typeLabel($0) }
            )
            .frame(maxWidth: 260, alignment: .leading)
            .onChange(of: keyType) { _, newValue in
                resetArrays(for: newValue)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var valueSection: some View {
        switch keyType {
        case "list":
            valueRows(
                values: $listValues,
                heading: "Values",
                placeholder: { "Value \($0 + 1)" },
                addLabel: "Add Value"
            )
        case "hash":
            pairRows(
                pairs: Binding(
                    get: { hashPairs.map { (first: $0.field, second: $0.value) } },
                    set: { hashPairs = $0.map { (field: $0.first, value: $0.second) } }
                ),
                heading: "Fields",
                firstPlaceholder: "Field",
                secondPlaceholder: "Value",
                addLabel: "Add Field"
            )
        case "set":
            valueRows(
                values: $setMembers,
                heading: "Members",
                placeholder: { "Member \($0 + 1)" },
                addLabel: "Add Member"
            )
        case "zset":
            pairRows(
                pairs: Binding(
                    get: { zsetPairs.map { (first: $0.score, second: $0.member) } },
                    set: { zsetPairs = $0.map { (score: $0.first, member: $0.second) } }
                ),
                heading: "Members",
                firstPlaceholder: "Score",
                secondPlaceholder: "Member",
                addLabel: "Add Member",
                firstWidth: AppSize.formFieldWidth
            )
        default:
            stringRow
        }
    }

    private var stringRow: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Text("Value")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: AppSize.formLabelWidthCompact, alignment: .leading)
            TextField("Value", text: $keyValue, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
                .font(AppFont.monoSubheadline)
        }
    }

    private func valueRows(
        values: Binding<[String]>,
        heading: String,
        placeholder: @escaping (Int) -> String,
        addLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            sectionHeader(
                title: "\(heading) (\(values.wrappedValue.count))",
                addLabel: addLabel
            ) {
                values.wrappedValue.append("")
            }
            ForEach(values.wrappedValue.indices, id: \.self) { index in
                HStack(spacing: AppSpacing.small) {
                    TextField(
                        placeholder(index),
                        text: Binding(
                            get: { values.wrappedValue[index] },
                            set: { values.wrappedValue[index] = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(AppFont.monoSubheadline)
                    removeButton(disabled: values.wrappedValue.count <= 1) {
                        values.wrappedValue.remove(at: index)
                    }
                }
            }
        }
    }

    private func pairRows(
        pairs: Binding<[(first: String, second: String)]>,
        heading: String,
        firstPlaceholder: String,
        secondPlaceholder: String,
        addLabel: String,
        firstWidth: CGFloat? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            sectionHeader(
                title: "\(heading) (\(pairs.wrappedValue.count))",
                addLabel: addLabel
            ) {
                pairs.wrappedValue.append(("", ""))
            }
            ForEach(pairs.wrappedValue.indices, id: \.self) { index in
                HStack(spacing: AppSpacing.small) {
                    TextField(
                        firstPlaceholder,
                        text: Binding(
                            get: { pairs.wrappedValue[index].first },
                            set: { pairs.wrappedValue[index].first = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(AppFont.monoSubheadline)
                    .modifier(ConditionalWidth(width: firstWidth))
                    TextField(
                        secondPlaceholder,
                        text: Binding(
                            get: { pairs.wrappedValue[index].second },
                            set: { pairs.wrappedValue[index].second = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(AppFont.monoSubheadline)
                    removeButton(disabled: pairs.wrappedValue.count <= 1) {
                        pairs.wrappedValue.remove(at: index)
                    }
                }
            }
        }
    }

    private func sectionHeader(title: String, addLabel: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
            Button(action: action) {
                Label(addLabel, systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }

    private func removeButton(disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .disabled(disabled)
    }

    // MARK: Actions

    private func save() {
        switch keyType {
        case "list":
            onSave(keyName, keyType, listValues.joined(separator: "\n"))
        case "hash":
            let pairs = hashPairs.map { "\($0.field):\($0.value)" }.joined(separator: "\n")
            onSave(keyName, keyType, pairs)
        case "set":
            onSave(keyName, keyType, setMembers.joined(separator: "\n"))
        case "zset":
            let pairs = zsetPairs.map { "\($0.score):\($0.member)" }.joined(separator: "\n")
            onSave(keyName, keyType, pairs)
        default:
            onSave(keyName, keyType, keyValue)
        }
    }

    private func typeLabel(_ type: String) -> String {
        switch type {
        case "string": return "String"
        case "list": return "List"
        case "hash": return "Hash"
        case "set": return "Set"
        case "zset": return "Sorted Set"
        default: return type
        }
    }
}

private struct ConditionalWidth: ViewModifier {
    let width: CGFloat?

    func body(content: Content) -> some View {
        if let width {
            content.frame(width: width)
        } else {
            content
        }
    }
}
