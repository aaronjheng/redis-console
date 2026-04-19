import Foundation
import Network

// MARK: - RESP Protocol Version

enum RESPProtocolVersion: Sendable {
    case resp2
    case resp3
}

// MARK: - RESP Map Entry (for RESP3 maps)

struct RESPMapEntry: Sendable {
    let key: RESPValue
    let value: RESPValue
}

// MARK: - RESP2/RESP3 Protocol Parser

enum RESPValue: CustomStringConvertible, Sendable {
    case simpleString(String)
    case error(String)
    case integer(Int)
    case bulkString(String?)
    case array([RESPValue?])
    case map([RESPMapEntry])  // RESP3 map type
    case null
    case boolean(Bool)         // RESP3 boolean
    case double(Double)        // RESP3 double

    var description: String {
        switch self {
        case .simpleString(let string): return string
        case .error(let message): return "(error) \(message)"
        case .integer(let integer): return "(integer) \(integer)"
        case .bulkString(let string): return string ?? "(nil)"
        case .array(let values):
            return values.enumerated().map { index, value in
                "\(index + 1)) \(value?.description ?? "(nil)")"
            }.joined(separator: "\n")
        case .map(let entries):
            return entries.map { entry in
                "\(entry.key.description): \(entry.value.description)"
            }.joined(separator: "\n")
        case .null: return "(nil)"
        case .boolean(let value): return value ? "true" : "false"
        case .double(let value): return String(value)
        }
    }

    var displayString: String {
        switch self {
        case .simpleString(let string): return string
        case .error(let message): return "ERR \(message)"
        case .integer(let integer): return "\(integer)"
        case .bulkString(let string): return string ?? "(nil)"
        case .array(let values):
            return values.enumerated().map { index, value in
                let content = value?.displayString ?? "(nil)"
                return "\(index + 1)) \(content)"
            }.joined(separator: "\n")
        case .map(let entries):
            return entries.map { entry in
                "\(entry.key.displayString): \(entry.value.displayString)"
            }.joined(separator: "\n")
        case .null: return "(nil)"
        case .boolean(let value): return value ? "true" : "false"
        case .double(let value): return String(value)
        }
    }

    var isArray: Bool {
        if case .array = self { return true }
        return false
    }

    var arrayValues: [RESPValue?] {
        if case .array(let values) = self { return values }
        return []
    }

    var string: String? {
        switch self {
        case .simpleString(let string): return string
        case .bulkString(let string): return string
        default: return nil
        }
    }

    var intValue: Int? {
        if case .integer(let integer) = self { return integer }
        return nil
    }
}

class RESPParser {
    private var buffer = Data()

    func append(_ data: Data) {
        buffer.append(data)
    }

    func parse() -> RESPValue? {
        guard !buffer.isEmpty else { return nil }
        let snapshot = buffer
        let result = parseValue()
        if result == nil {
            buffer = snapshot
        }
        return result
    }

    private func parseValue() -> RESPValue? {
        guard let firstByte = buffer.first else { return nil }

        switch firstByte {
        case 0x2B:  // '+'
            return parseSimpleString()
        case 0x2D:  // '-'
            return parseError()
        case 0x3A:  // ':'
            return parseInteger()
        case 0x24:  // '$'
            return parseBulkString()
        case 0x2A:  // '*'
            return parseArray()
        default:
            return nil
        }
    }

    private func readLine() -> String? {
        guard let crIndex = buffer.firstIndex(of: 0x0D) else { return nil }
        let lineData = buffer[buffer.startIndex..<crIndex]
        guard crIndex + 1 < buffer.endIndex, buffer[crIndex + 1] == 0x0A else { return nil }
        let line = String(data: lineData, encoding: .utf8)
        buffer.removeSubrange(buffer.startIndex...crIndex + 1)
        return line
    }

    private func parseSimpleString() -> RESPValue? {
        buffer.removeFirst()  // remove '+'
        guard let line = readLine() else { return nil }
        return .simpleString(line)
    }

    private func parseError() -> RESPValue? {
        buffer.removeFirst()  // remove '-'
        guard let line = readLine() else { return nil }
        return .error(line)
    }

    private func parseInteger() -> RESPValue? {
        buffer.removeFirst()  // remove ':'
        guard let line = readLine(), let val = Int(line) else { return nil }
        return .integer(val)
    }

    private func parseBulkString() -> RESPValue? {
        buffer.removeFirst()  // remove '$'
        guard let line = readLine(), let len = Int(line) else { return nil }
        if len == -1 { return .bulkString(nil) }
        guard buffer.count >= len + 2 else { return nil }
        let strData = buffer[buffer.startIndex..<buffer.startIndex + len]
        buffer.removeSubrange(buffer.startIndex...buffer.startIndex + len + 1)
        let str = String(data: strData, encoding: .utf8) ?? ""
        return .bulkString(str)
    }

    private func parseArray() -> RESPValue? {
        buffer.removeFirst()  // remove '*'
        guard let line = readLine(), let count = Int(line) else { return nil }
        if count == -1 { return .array([]) }
        if count == 0 { return .array([]) }
        var items: [RESPValue?] = []
        for _ in 0..<count {
            if let val = parseValue() {
                items.append(val)
            } else {
                return nil
            }
        }
        return .array(items)
    }
}

// MARK: - RESP Encoder

struct RESPEncoder {
    static func encode(_ args: [String]) -> Data {
        // Default to RESP2 encoding
        encode(args, version: .resp2)
    }

    static func encode(_ args: [String], version: RESPProtocolVersion) -> Data {
        var data = Data()
        data.append(contentsOf: "*\(args.count)\r\n".utf8)
        for arg in args {
            let bytes = Data(arg.utf8)
            data.append(contentsOf: "$\(bytes.count)\r\n".utf8)
            data.append(bytes)
            data.append(contentsOf: "\r\n".utf8)
        }
        return data
    }
}
