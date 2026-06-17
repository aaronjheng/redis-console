import SwiftUI

// MARK: - String Detail View

struct StringDetailView: View {
    let key: String
    let value: String
    @Binding var format: StringValueFormat
    let onSave: (String) -> Void

    @State private var isEditing = false
    @State private var editValue = ""

    private var isJson: Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private var beautifiedValue: String {
        guard
            let data = value.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted),
            let prettyString = String(data: prettyData, encoding: .utf8)
        else {
            return value
        }
        return prettyString
    }

    private var displayedValue: String {
        switch format {
        case .raw:
            return value
        case .unicode:
            return unicodeEscapedValue
        case .json:
            return isJson ? beautifiedValue : value
        case .ascii:
            return asciiValue
        case .hex:
            return hexValue
        case .base64:
            return base64DecodedValue
        case .base64Encode:
            return base64EncodedValue
        case .gzip:
            return gzipDecompressedValue
        }
    }

    private var highlightedBeautifiedValue: AttributedString {
        JSONSyntaxHighlighter.highlight(beautifiedValue)
    }

    private var unicodeEscapedValue: String {
        value.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0x0A:
                return "\\n"
            case 0x0D:
                return "\\r"
            case 0x09:
                return "\\t"
            case 0x20...0x7E:
                return String(scalar)
            default:
                return "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
            }
        }.joined()
    }

    private var asciiValue: String {
        String(
            value.utf8.map { byte in
                if (32...126).contains(byte), let scalar = UnicodeScalar(Int(byte)) {
                    return Character(scalar)
                }
                return "."
            }
        )
    }

    private var hexValue: String {
        value.utf8.enumerated().map { index, byte in
            let separator = index > 0 && index % 16 == 0 ? "\n" : " "
            let prefix = index == 0 ? "" : separator
            return prefix + String(format: "%02X", byte)
        }.joined()
    }

    private var base64DecodedValue: String {
        guard let data = Data(base64Encoded: value),
            let decoded = String(data: data, encoding: .utf8)
        else {
            return "Invalid Base64 data"
        }
        return decoded
    }

    private var base64EncodedValue: String {
        guard let data = value.data(using: .utf8) else {
            return "Unable to encode"
        }
        return data.base64EncodedString()
    }

    private var gzipDecompressedValue: String {
        guard let data = Data(base64Encoded: value) ?? value.data(using: .utf8) else {
            return "Unable to read data"
        }
        guard !data.isEmpty else { return value }
        do {
            let decompressed = try (data as NSData).decompressed(using: .zlib) as Data
            guard let result = String(data: decompressed, encoding: .utf8) else {
                return "Decompressed data is not valid UTF-8"
            }
            return result
        } catch {
            return "GZip decompression failed: \(error.localizedDescription)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isEditing {
                VStack(spacing: 8) {
                    TextEditor(text: $editValue)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.accentColor, lineWidth: 2)
                        )

                    HStack(spacing: 8) {
                        Spacer()
                        Button("Cancel") {
                            isEditing = false
                        }
                        .buttonStyle(.borderless)
                        Button("Save") {
                            onSave(editValue)
                            isEditing = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            } else {
                ZStack(alignment: .topTrailing) {
                    ScrollView {
                        Group {
                            if format == .json && isJson {
                                Text(highlightedBeautifiedValue)
                            } else {
                                Text(displayedValue)
                            }
                        }
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                    .onTapGesture(count: 2) {
                        editValue = value
                        isEditing = true
                    }

                    HStack(spacing: 4) {
                        Picker("", selection: $format) {
                            ForEach(StringValueFormat.allCases) { format in
                                Text(format.title).tag(format)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        .help("Value format")

                        Button("Edit Value", systemImage: "pencil") {
                            editValue = value
                            isEditing = true
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Edit value")
                    }
                    .padding()
                }
            }

        }
    }
}

private enum JSONSyntaxHighlighter {
    static func highlight(_ source: String) -> AttributedString {
        var attributed = AttributedString(source)
        attributed.foregroundColor = .primary

        let chars = Array(source)
        var index = 0

        while index < chars.count {
            let char = chars[index]

            if char == "\"" {
                let stringStart = index
                index += 1
                var escapeRanges: [Range<Int>] = []

                while index < chars.count {
                    if chars[index] == "\\" {
                        let escapeStart = index
                        index += 1
                        if index < chars.count {
                            index += 1
                        }
                        escapeRanges.append(escapeStart..<index)
                        continue
                    }
                    if chars[index] == "\"" {
                        index += 1
                        break
                    }
                    index += 1
                }

                let stringRange = stringStart..<index
                let isObjectKey = isObjectKeyString(chars: chars, tokenRange: stringRange)
                applyColor(
                    to: &attributed,
                    source: source,
                    range: stringRange,
                    color: isObjectKey ? .teal : .green
                )
                for escapeRange in escapeRanges {
                    applyColor(to: &attributed, source: source, range: escapeRange, color: .orange)
                }
                continue
            }

            if isNumberStart(char: char, next: index + 1 < chars.count ? chars[index + 1] : nil) {
                let numberStart = index
                index += 1
                while index < chars.count, isNumberBody(char: chars[index]) {
                    index += 1
                }
                applyColor(to: &attributed, source: source, range: numberStart..<index, color: .blue)
                continue
            }

            if let keyword = keyword(at: index, chars: chars) {
                let end = index + keyword.count
                let color: Color =
                    switch keyword {
                    case "true", "false":
                        .orange
                    case "null":
                        .red
                    default:
                        .primary
                    }
                applyColor(to: &attributed, source: source, range: index..<end, color: color)
                index = end
                continue
            }

            if "{}[],:".contains(char) {
                applyColor(to: &attributed, source: source, range: index..<(index + 1), color: .secondary)
            }

            index += 1
        }

        return attributed
    }

    private static func applyColor(to attributed: inout AttributedString, source: String, range: Range<Int>, color: Color) {
        guard let lower = source.index(source.startIndex, offsetBy: range.lowerBound, limitedBy: source.endIndex),
            let upper = source.index(source.startIndex, offsetBy: range.upperBound, limitedBy: source.endIndex),
            let attributedRange = Range(lower..<upper, in: attributed)
        else {
            return
        }
        attributed[attributedRange].foregroundColor = color
    }

    private static func isObjectKeyString(chars: [Character], tokenRange: Range<Int>) -> Bool {
        var lookahead = tokenRange.upperBound
        while lookahead < chars.count, chars[lookahead].isWhitespace {
            lookahead += 1
        }
        return lookahead < chars.count && chars[lookahead] == ":"
    }

    private static func isNumberStart(char: Character, next: Character?) -> Bool {
        if char.isNumber {
            return true
        }
        if char == "-", let next, next.isNumber {
            return true
        }
        return false
    }

    private static func isNumberBody(char: Character) -> Bool {
        char.isNumber || char == "." || char == "e" || char == "E" || char == "+" || char == "-"
    }

    private static func keyword(at index: Int, chars: [Character]) -> String? {
        for keyword in ["true", "false", "null"] {
            let end = index + keyword.count
            guard end <= chars.count else { continue }
            if String(chars[index..<end]) != keyword { continue }
            let previous = index > 0 ? chars[index - 1] : nil
            let next = end < chars.count ? chars[end] : nil
            if let previous, isIdentifierCharacter(previous) {
                continue
            }
            if let next, isIdentifierCharacter(next) {
                continue
            }
            return keyword
        }
        return nil
    }

    private static func isIdentifierCharacter(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_"
    }
}
