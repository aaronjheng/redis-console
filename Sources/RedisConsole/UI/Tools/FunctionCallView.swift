import SwiftUI

// MARK: - Function Call View

struct FunctionCallView: View {
    @Environment(ConnectionState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let library: RedisFunctionLibrary

    @State private var selectedFunctionName: String
    @State private var useReadOnly: Bool
    @State private var keys: [String] = [""]
    @State private var args: [String] = [""]
    @State private var error: String?

    init(library: RedisFunctionLibrary) {
        self.library = library
        let first = library.functions.first
        _selectedFunctionName = State(initialValue: first?.name ?? "")
        _useReadOnly = State(initialValue: first?.isReadOnly ?? false)
    }

    private var selectedFunction: RedisFunction? {
        library.functions.first { $0.name == selectedFunctionName }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            configurationSection
            Divider()
            resultSection
            Divider()
            actions
        }
        .frame(width: 640, height: 560)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "play.circle")
                .foregroundStyle(Color.accentColor)
            Text("Call Function")
                .font(.headline)
            Text(library.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(AppSpacing.large)
    }

    // MARK: Configuration

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            functionPickerRow
            readOnlyRow
            keysSection
            argsSection
        }
        .padding(AppSpacing.large)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var functionPickerRow: some View {
        HStack(spacing: AppSpacing.medium) {
            Text("Function")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            OptionsPicker(
                "Select function",
                selection: $selectedFunctionName,
                options: library.functions.map(\.name),
                label: { $0 }
            )
            .frame(maxWidth: 260, alignment: .leading)
            if let fn = selectedFunction {
                if fn.isReadOnly {
                    Badge(
                        text: "no-writes",
                        foregroundColor: AppColor.success,
                        backgroundColor: AppColor.success.opacity(0.14)
                    )
                }
            }
            Spacer()
        }
    }

    private var readOnlyRow: some View {
        HStack(spacing: AppSpacing.medium) {
            Text("Mode")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            BinaryTogglePicker(
                selection: $useReadOnly,
                first: false,
                second: true,
                firstLabel: { Text("FCALL").font(.caption) },
                secondLabel: { Text("FCALL_RO").font(.caption) }
            )
            .frame(width: 150)
            .help("FCALL allows writes; FCALL_RO is read-only and runs on replicas")
            Spacer()
        }
    }

    private var keysSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack {
                Text("Keys (\(keys.count))")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    keys.append("")
                } label: {
                    Label("Add Key", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            ForEach(keys.indices, id: \.self) { index in
                HStack(spacing: AppSpacing.small) {
                    TextField(
                        "key \(index + 1)",
                        text: Binding(
                            get: { keys[index] },
                            set: { keys[index] = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(AppFont.monoSubheadline)
                    Button {
                        removeLine(at: index, from: &keys)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(keys.count <= 1)
                }
            }
        }
    }

    private var argsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack {
                Text("Args (\(args.count))")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    args.append("")
                } label: {
                    Label("Add Arg", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            ForEach(args.indices, id: \.self) { index in
                HStack(spacing: AppSpacing.small) {
                    TextField(
                        "arg \(index + 1)",
                        text: Binding(
                            get: { args[index] },
                            set: { args[index] = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(AppFont.monoSubheadline)
                    Button {
                        removeLine(at: index, from: &args)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(args.count <= 1)
                }
            }
        }
    }

    private func removeLine(at index: Int, from array: inout [String]) {
        if array.count > 1 {
            array.remove(at: index)
        }
    }

    // MARK: Result

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Result")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if app.isCallingFunction {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.small)
            Divider()

            Group {
                if let result = app.lastFunctionCallResult {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppSpacing.small) {
                            HStack(spacing: AppSpacing.small) {
                                Text(result.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Text(commandText(for: result))
                                    .font(AppFont.monoCaption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            if let errorMessage = result.error {
                                Text(errorMessage)
                                    .font(AppFont.monoSubheadline)
                                    .foregroundStyle(AppColor.error)
                                    .textSelection(.enabled)
                            } else {
                                RESPValueView(value: result.response)
                                    .font(AppFont.monoSubheadline)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppSpacing.large)
                    }
                } else {
                    Text("Run a function to see its result.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(AppSpacing.large)
                }
            }
            .frame(maxHeight: .infinity)
            .background(AppColor.codeBackground)
        }
    }

    private func commandText(for result: RedisFunctionCallResult) -> String {
        var parts = [result.isReadOnly ? "FCALL_RO" : "FCALL", result.functionName, "\(result.keys.count)"]
        parts.append(contentsOf: result.keys)
        parts.append(contentsOf: result.args)
        return parts.joined(separator: " ")
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: AppSpacing.small) {
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(AppColor.error)
                    .lineLimit(1)
            }
            Spacer()
            Button("Close", role: .cancel) { dismiss() }
            Button {
                Task { await runCall() }
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(app.isCallingFunction || selectedFunctionName.isEmpty)
        }
        .padding(AppSpacing.large)
    }

    private func runCall() async {
        error = nil
        let nonEmptyKeys = keys.map { $0 }.filter { !$0.isEmpty }
        // Keep at least the count honest: FCALL numkeys must match provided keys.
        // Empty trailing lines are dropped; numkeys reflects actual key count.
        let nonEmptyArgs = args.filter { !$0.isEmpty }
        await app.callFunction(
            name: selectedFunctionName,
            keys: nonEmptyKeys,
            args: nonEmptyArgs,
            isReadOnly: useReadOnly
        )
    }
}

// MARK: - RESP Value Renderer

private struct RESPValueView: View {
    let value: RESPValue
    var depth: Int = 0

    var body: some View {
        switch value {
        case .integer(let intValue):
            Text("(integer) \(intValue)")
                .foregroundStyle(AppColor.syntaxNumber)
        case .double(let doubleValue):
            Text("(double) \(doubleValue)")
                .foregroundStyle(AppColor.syntaxNumber)
        case .bulkString(let string):
            Text(string ?? "(nil)")
                .foregroundStyle(string == nil ? AppColor.syntaxNull : AppColor.syntaxString)
        case .simpleString(let string):
            Text(string)
                .foregroundStyle(AppColor.syntaxString)
        case .error(let message):
            Text("(error) \(message)")
                .foregroundStyle(AppColor.error)
        case .boolean(let boolValue):
            Text(boolValue ? "true" : "false")
                .foregroundStyle(AppColor.syntaxBool)
        case .null:
            Text("(nil)")
                .foregroundStyle(AppColor.syntaxNull)
        case .array(let values):
            if values.isEmpty {
                Text("(empty array)")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, element in
                        HStack(alignment: .top, spacing: AppSpacing.small) {
                            Text("\(index + 1))")
                                .foregroundStyle(.secondary)
                            if let element {
                                RESPValueView(value: element, depth: depth + 1)
                            } else {
                                Text("(nil)")
                                    .foregroundStyle(AppColor.syntaxNull)
                            }
                        }
                    }
                }
                .padding(.leading, depth == 0 ? 0 : AppSpacing.small)
            }
        case .map(let entries):
            if entries.isEmpty {
                Text("(empty map)")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        HStack(alignment: .top, spacing: AppSpacing.small) {
                            RESPValueView(value: entry.key, depth: depth + 1)
                            Text(":")
                                .foregroundStyle(AppColor.syntaxPunctuation)
                            RESPValueView(value: entry.value, depth: depth + 1)
                        }
                    }
                }
            }
        }
    }
}
