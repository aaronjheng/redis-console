import Foundation
import Network

// MARK: - RESP Protocol Version

enum RESPProtocolVersion: Sendable {
    case resp2
    case resp3

    var helloArgument: String {
        switch self {
        case .resp2: return "2"
        case .resp3: return "3"
        }
    }

    var logName: String {
        switch self {
        case .resp2: return "RESP2"
        case .resp3: return "RESP3"
        }
    }
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
    case map([RESPMapEntry])
    case null
    case boolean(Bool)
    case double(Double)

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

    var keyValuePairs: [(key: RESPValue, value: RESPValue)] {
        switch self {
        case .array(let values):
            var pairs: [(key: RESPValue, value: RESPValue)] = []
            var index = 0
            while index + 1 < values.count {
                if let key = values[index], let value = values[index + 1] {
                    pairs.append((key: key, value: value))
                }
                index += 2
            }
            return pairs
        case .map(let entries):
            return entries.map { (key: $0.key, value: $0.value) }
        default:
            return []
        }
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

// MARK: - RESP Parsed Message

enum RESPMessage: Sendable {
    case response(RESPValue)
    case push(RESPValue)
}

struct RESPParser: Sendable {
    private var buffer = Data()
    private var readIndex: Data.Index = 0

    mutating func append(_ data: Data) {
        buffer.append(data)
    }

    /// Drop bytes that have already been consumed by `parse()`, keeping only
    /// the trailing fragment that is not yet a complete RESP value.
    mutating func compact() {
        guard readIndex > buffer.startIndex else { return }
        buffer.removeSubrange(buffer.startIndex..<readIndex)
        readIndex = buffer.startIndex
    }

    /// Parse a single complete top-level RESP value, if one is fully buffered.
    ///
    /// Returns `nil` when the buffered data does not yet contain a complete
    /// value. On failure nothing is consumed, so additional data can be appended
    /// and parsing retried without re-scanning already-processed bytes.
    mutating func parse() -> RESPMessage? {
        guard readIndex < buffer.endIndex else { return nil }
        let start = readIndex
        let firstByte = buffer[readIndex]

        // RESP3 push frames ('>') are unsolicited and must not be matched
        // against an in-flight request, so they are surfaced separately.
        if firstByte == 0x3E {
            guard let value = parseValue() else {
                readIndex = start
                return nil
            }
            return .push(value)
        }

        guard let value = parseValue() else {
            readIndex = start
            return nil
        }
        return .response(value)
    }

    private mutating func parseValue() -> RESPValue? {
        guard readIndex < buffer.endIndex else { return nil }

        let firstByte = buffer[readIndex]
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
        case 0x5F:  // '_'
            return parseNull()
        case 0x23:  // '#'
            return parseBoolean()
        case 0x2C:  // ','
            return parseDouble()
        case 0x28:  // '('
            return parseBigNumber()
        case 0x21:  // '!'
            return parseBlobError()
        case 0x3D:  // '='
            return parseVerbatimString()
        case 0x25:  // '%'
            return parseMap()
        case 0x7E:  // '~'
            return parseSet()
        case 0x3E:  // '>'
            return parsePush()
        case 0x7C:  // '|'
            return parseAttribute()
        default:
            return nil
        }
    }

    private mutating func readLine() -> String? {
        var search = readIndex
        while search < buffer.endIndex {
            if buffer[search] == 0x0D {
                let lineFeedIndex = buffer.index(after: search)
                guard lineFeedIndex < buffer.endIndex, buffer[lineFeedIndex] == 0x0A else { return nil }
                let lineData = buffer[readIndex..<search]
                guard let line = String(data: lineData, encoding: .utf8) else { return nil }
                readIndex = buffer.index(after: lineFeedIndex)
                return line
            }
            search = buffer.index(after: search)
        }
        return nil
    }

    private mutating func parseSimpleString() -> RESPValue? {
        readIndex = buffer.index(after: readIndex)  // remove '+'
        guard let line = readLine() else { return nil }
        return .simpleString(line)
    }

    private mutating func parseError() -> RESPValue? {
        readIndex = buffer.index(after: readIndex)  // remove '-'
        guard let line = readLine() else { return nil }
        return .error(line)
    }

    private mutating func parseInteger() -> RESPValue? {
        readIndex = buffer.index(after: readIndex)  // remove ':'
        guard let line = readLine(), let val = Int(line) else { return nil }
        return .integer(val)
    }

    private mutating func parseBulkString() -> RESPValue? {
        readIndex = buffer.index(after: readIndex)  // remove '$'
        guard let line = readLine(), let len = Int(line) else { return nil }
        if len == -1 { return .bulkString(nil) }
        guard let string = readPayload(length: len) else { return nil }
        return .bulkString(string)
    }

    private mutating func parseArray() -> RESPValue? {
        guard let items = parseAggregateItems() else { return nil }
        return .array(items)
    }

    private mutating func parseNull() -> RESPValue? {
        readIndex = buffer.index(after: readIndex)  // remove '_'
        guard readLine() == "" else { return nil }
        return .null
    }

    private mutating func parseBoolean() -> RESPValue? {
        readIndex = buffer.index(after: readIndex)  // remove '#'
        guard let line = readLine() else { return nil }
        switch line {
        case "t": return .boolean(true)
        case "f": return .boolean(false)
        default: return nil
        }
    }

    private mutating func parseDouble() -> RESPValue? {
        readIndex = buffer.index(after: readIndex)  // remove ','
        guard let line = readLine() else { return nil }
        switch line.lowercased() {
        case "inf": return .double(.infinity)
        case "-inf": return .double(-.infinity)
        case "nan": return .double(.nan)
        default:
            guard let value = Double(line) else { return nil }
            return .double(value)
        }
    }

    private mutating func parseBigNumber() -> RESPValue? {
        readIndex = buffer.index(after: readIndex)  // remove '('
        guard let line = readLine() else { return nil }
        return .bulkString(line)
    }

    private mutating func parseBlobError() -> RESPValue? {
        readIndex = buffer.index(after: readIndex)  // remove '!'
        guard let line = readLine(), let len = Int(line), let message = readPayload(length: len) else { return nil }
        return .error(message)
    }

    private mutating func parseVerbatimString() -> RESPValue? {
        readIndex = buffer.index(after: readIndex)  // remove '='
        guard let line = readLine(), let len = Int(line), let string = readPayload(length: len) else { return nil }
        guard string.count >= 4 else { return .bulkString(string) }
        return .bulkString(String(string.dropFirst(4)))
    }

    private mutating func parseMap() -> RESPValue? {
        readIndex = buffer.index(after: readIndex)  // remove '%'
        guard let line = readLine(), let count = Int(line) else { return nil }
        if count == -1 { return .null }
        if count == 0 { return .map([]) }
        guard count > 0 else { return nil }
        var entries: [RESPMapEntry] = []
        entries.reserveCapacity(count)
        for _ in 0..<count {
            guard let key = parseValue(), let value = parseValue() else {
                return nil
            }
            entries.append(RESPMapEntry(key: key, value: value))
        }
        return .map(entries)
    }

    private mutating func parseSet() -> RESPValue? {
        guard let items = parseAggregateItems() else { return nil }
        return .array(items)
    }

    private mutating func parsePush() -> RESPValue? {
        guard let items = parseAggregateItems() else { return nil }
        return .array(items)
    }

    private mutating func parseAttribute() -> RESPValue? {
        readIndex = buffer.index(after: readIndex)  // remove '|'
        guard let line = readLine(), let count = Int(line), count >= 0 else { return nil }
        for _ in 0..<count {
            guard parseValue() != nil, parseValue() != nil else {
                return nil
            }
        }
        return parseValue()
    }

    private mutating func parseAggregateItems() -> [RESPValue?]? {
        readIndex = buffer.index(after: readIndex)  // remove prefix byte
        guard let line = readLine(), let count = Int(line), count >= -1 else { return nil }
        if count == -1 { return [] }
        if count == 0 { return [] }
        var items: [RESPValue?] = []
        items.reserveCapacity(count)
        for _ in 0..<count {
            if let val = parseValue() {
                items.append(val)
            } else {
                return nil
            }
        }
        return items
    }

    private mutating func readPayload(length: Int) -> String? {
        guard length >= 0 else { return nil }
        let remaining = buffer.distance(from: readIndex, to: buffer.endIndex)
        guard remaining >= length + 2 else { return nil }

        let payloadEndIndex = buffer.index(readIndex, offsetBy: length)
        let lineFeedIndex = buffer.index(after: payloadEndIndex)
        guard buffer[payloadEndIndex] == 0x0D, buffer[lineFeedIndex] == 0x0A else {
            return nil
        }

        let payloadData = buffer[readIndex..<payloadEndIndex]
        readIndex = buffer.index(after: lineFeedIndex)
        return String(data: payloadData, encoding: .utf8) ?? ""
    }
}

// MARK: - RESP Encoder

struct RESPEncoder {
    static func encode(_ args: [String]) -> Data {
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
