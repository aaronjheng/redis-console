import Foundation
import Observation

// MARK: - Redis Key Entry

@Observable
class RedisKeyEntry: Identifiable, Hashable {
    let id = UUID()
    let key: String
    var type: String
    var ttl: Int?
    var size: Int?
    var length: Int?

    init(key: String, type: String, ttl: Int?, size: Int?, length: Int? = nil) {
        self.key = key
        self.type = type
        self.ttl = ttl
        self.size = size
        self.length = length
    }

    var icon: String {
        switch type {
        case "string": return "doc.text"
        case "list": return "list.bullet"
        case "hash": return "tablecells"
        case "set": return "circle.grid.cross"
        case "zset": return "arrow.up.arrow.down.circle"
        default: return "questionmark.circle"
        }
    }

    var ttlText: String {
        guard let ttl = ttl, ttl > 0 else { return "No limit" }
        if ttl > 86400 { return "\(ttl / 86400)d" }
        if ttl > 3600 { return "\(ttl / 3600)h" }
        if ttl > 60 { return "\(ttl / 60)m" }
        return "\(ttl)s"
    }

    var hasExpiry: Bool {
        guard let ttl else { return false }
        return ttl > 0
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }

    static func == (lhs: RedisKeyEntry, rhs: RedisKeyEntry) -> Bool {
        lhs.key == rhs.key
    }
}

enum KeyDetailZSetOrder: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ascending: return "Ascending"
        case .descending: return "Descending"
        }
    }
}

enum StringValueFormat: String, CaseIterable, Identifiable, Codable {
    case raw
    case unicode
    case json
    case ascii
    case hex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .raw: return "Raw"
        case .unicode: return "Unicode"
        case .json: return "JSON"
        case .ascii: return "ASCII"
        case .hex: return "Hex"
        }
    }
}

struct BulkDeletePreview: Identifiable {
    let id = UUID()
    let pattern: String
    let typeFilter: String
    let keys: [String]
    let scannedCount: Int
    let didReachLimit: Bool
    let duration: TimeInterval

    var typeText: String {
        typeFilter.isEmpty ? "all types" : typeFilter
    }
}

struct BulkDeleteResult {
    let processed: Int
    let deleted: Int
    let deletedKeys: [String]
    let usedFallback: Bool
    let duration: TimeInterval
}
