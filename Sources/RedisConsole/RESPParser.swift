import Foundation
import Network

// MARK: - RESP2 Protocol Parser

enum RESPValue: CustomStringConvertible {
    case simpleString(String)
    case error(String)
    case integer(Int)
    case bulkString(String?)
    case array([RESPValue?])
    case null

    var description: String {
        switch self {
        case .simpleString(let s): return s
        case .error(let s): return "(error) \(s)"
        case .integer(let i): return "(integer) \(i)"
        case .bulkString(let s): return s ?? "(nil)"
        case .array(let a):
            return a.enumerated().map { i, v in
                "\(i+1)) \(v?.description ?? "(nil)")"
            }.joined(separator: "\n")
        case .null: return "(nil)"
        }
    }

    var displayString: String {
        switch self {
        case .simpleString(let s): return s
        case .error(let s): return "ERR \(s)"
        case .integer(let i): return "\(i)"
        case .bulkString(let s): return s ?? "(nil)"
        case .array(let a):
            return a.enumerated().map { i, v in
                let content = v?.displayString ?? "(nil)"
                return "\(i+1)) \(content)"
            }.joined(separator: "\n")
        case .null: return "(nil)"
        }
    }

    var isArray: Bool {
        if case .array = self { return true }
        return false
    }

    var arrayValues: [RESPValue?] {
        if case .array(let a) = self { return a }
        return []
    }

    var string: String? {
        switch self {
        case .simpleString(let s): return s
        case .bulkString(let s): return s
        default: return nil
        }
    }

    var intValue: Int? {
        if case .integer(let i) = self { return i }
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
        let result = parseValue()
        return result
    }

    private func parseValue() -> RESPValue? {
        guard let firstByte = buffer.first else { return nil }

        switch firstByte {
        case 0x2B: // '+'
            return parseSimpleString()
        case 0x2D: // '-'
            return parseError()
        case 0x3A: // ':'
            return parseInteger()
        case 0x24: // '$'
            return parseBulkString()
        case 0x2A: // '*'
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
        buffer.removeFirst() // remove '+'
        guard let line = readLine() else { return nil }
        return .simpleString(line)
    }

    private func parseError() -> RESPValue? {
        buffer.removeFirst() // remove '-'
        guard let line = readLine() else { return nil }
        return .error(line)
    }

    private func parseInteger() -> RESPValue? {
        buffer.removeFirst() // remove ':'
        guard let line = readLine(), let val = Int(line) else { return nil }
        return .integer(val)
    }

    private func parseBulkString() -> RESPValue? {
        buffer.removeFirst() // remove '$'
        guard let line = readLine(), let len = Int(line) else { return nil }
        if len == -1 { return .bulkString(nil) }
        guard buffer.count >= len + 2 else { return nil }
        let strData = buffer[buffer.startIndex..<buffer.startIndex + len]
        buffer.removeSubrange(buffer.startIndex...buffer.startIndex + len + 1)
        let str = String(data: strData, encoding: .utf8) ?? ""
        return .bulkString(str)
    }

    private func parseArray() -> RESPValue? {
        buffer.removeFirst() // remove '*'
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
