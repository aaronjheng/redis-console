import SwiftUI

// MARK: - Edit Sheets

struct AddHashFieldSheet: View {
    let key: String
    @Binding var field: String
    @Binding var value: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        SheetLayout(
            title: "Add Hash Field",
            cancelAction: onCancel,
            primaryActionTitle: "Add",
            isPrimaryDisabled: field.isEmpty,
            primaryAction: { onSave(field, value) },
            content: {
                Form {
                    TextField("Field name", text: $field)
                    TextField("Value", text: $value, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
        )
    }
}

struct AddListElementSheet: View {
    let key: String
    @Binding var value: String
    @Binding var position: KeyDetailView.ListPosition
    let onSave: (String, KeyDetailView.ListPosition) -> Void
    let onCancel: () -> Void

    var body: some View {
        SheetLayout(
            title: "Add List Element",
            cancelAction: onCancel,
            primaryActionTitle: "Add",
            isPrimaryDisabled: value.isEmpty,
            primaryAction: { onSave(value, position) },
            content: {
                Form {
                    TextField("Value", text: $value, axis: .vertical)
                        .lineLimit(3...6)
                    Picker("Position", selection: $position) {
                        Text("Head (LPUSH)").tag(KeyDetailView.ListPosition.head)
                        Text("Tail (RPUSH)").tag(KeyDetailView.ListPosition.tail)
                    }
                }
            }
        )
    }
}

struct AddSetMemberSheet: View {
    let key: String
    @Binding var member: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        SheetLayout(
            title: "Add Set Member",
            cancelAction: onCancel,
            primaryActionTitle: "Add",
            isPrimaryDisabled: member.isEmpty,
            primaryAction: { onSave(member) },
            content: {
                Form {
                    TextField("Member value", text: $member, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
        )
    }
}

struct AddZSetMemberSheet: View {
    let key: String
    @Binding var member: String
    @Binding var score: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        SheetLayout(
            title: "Add Sorted Set Member",
            cancelAction: onCancel,
            primaryActionTitle: "Add",
            isPrimaryDisabled: member.isEmpty || score.isEmpty,
            primaryAction: { onSave(member, score) },
            content: {
                Form {
                    TextField("Member", text: $member)
                    TextField("Score", text: $score)
                }
            }
        )
    }
}

// MARK: - Editable Identifiers

extension String: @retroactive Identifiable {
    public var id: String { self }
}

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
        SheetLayout(
            title: "Add New Key",
            cancelAction: onCancel,
            primaryActionTitle: "Add",
            isPrimaryDisabled: keyName.isEmpty,
            primaryAction: {
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
            },
            content: {
                Form {
                    TextField("Key name", text: $keyName)
                    Picker("Type", selection: $keyType) {
                        Text("String").tag("string")
                        Text("List").tag("list")
                        Text("Hash").tag("hash")
                        Text("Set").tag("set")
                        Text("Sorted Set").tag("zset")
                    }
                    .onChange(of: keyType) { _, newValue in
                        resetArrays(for: newValue)
                    }

                    switch keyType {
                    case "list":
                        dynamicValueRows(
                            values: $listValues,
                            placeholder: { "Value \($0 + 1)" },
                            addLabel: "Add Value"
                        )
                    case "hash":
                        dynamicPairRows(
                            pairs: $hashPairs,
                            firstPlaceholder: "Field",
                            secondPlaceholder: "Value",
                            addLabel: "Add Field"
                        )
                    case "set":
                        dynamicValueRows(
                            values: $setMembers,
                            placeholder: { "Member \($0 + 1)" },
                            addLabel: "Add Member"
                        )
                    case "zset":
                        dynamicZSetRows(
                            pairs: $zsetPairs,
                            addLabel: "Add Member"
                        )
                    default:
                        TextField("Value", text: $keyValue, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
            }
        )
        .onAppear {
            resetArrays(for: keyType)
        }
    }

    @ViewBuilder
    private func dynamicValueRows(
        values: Binding<[String]>,
        placeholder: @escaping (Int) -> String,
        addLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(values.wrappedValue.enumerated()), id: \.offset) { index, _ in
                HStack {
                    TextField(
                        placeholder(index),
                        text: Binding(
                            get: { values.wrappedValue[index] },
                            set: { values.wrappedValue[index] = $0 }
                        ))
                    if values.wrappedValue.count > 1 {
                        Button {
                            values.wrappedValue.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Button {
                values.wrappedValue.append("")
            } label: {
                Label(addLabel, systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func dynamicPairRows(
        pairs: Binding<[(field: String, value: String)]>,
        firstPlaceholder: String,
        secondPlaceholder: String,
        addLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(pairs.wrappedValue.enumerated()), id: \.offset) { index, _ in
                HStack {
                    TextField(
                        firstPlaceholder,
                        text: Binding(
                            get: { pairs.wrappedValue[index].field },
                            set: { pairs.wrappedValue[index].field = $0 }
                        ))
                    TextField(
                        secondPlaceholder,
                        text: Binding(
                            get: { pairs.wrappedValue[index].value },
                            set: { pairs.wrappedValue[index].value = $0 }
                        ))
                    if pairs.wrappedValue.count > 1 {
                        Button {
                            pairs.wrappedValue.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Button {
                pairs.wrappedValue.append(("", ""))
            } label: {
                Label(addLabel, systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func dynamicZSetRows(
        pairs: Binding<[(score: String, member: String)]>,
        addLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(pairs.wrappedValue.enumerated()), id: \.offset) { index, _ in
                HStack {
                    TextField(
                        "Score",
                        text: Binding(
                            get: { pairs.wrappedValue[index].score },
                            set: { pairs.wrappedValue[index].score = $0 }
                        )
                    )
                    .frame(width: 80)
                    TextField(
                        "Member",
                        text: Binding(
                            get: { pairs.wrappedValue[index].member },
                            set: { pairs.wrappedValue[index].member = $0 }
                        ))
                    if pairs.wrappedValue.count > 1 {
                        Button {
                            pairs.wrappedValue.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Button {
                pairs.wrappedValue.append(("", ""))
            } label: {
                Label(addLabel, systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }
}
