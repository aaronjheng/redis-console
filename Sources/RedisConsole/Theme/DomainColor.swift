import SwiftUI

enum DomainColor {
    static let statusSuccess: Color = .green
    static let statusWarning: Color = .orange
    static let statusError: Color = .red
    static let statusInfo: Color = .blue

    static let typeString: Color = .blue
    static let typeList: Color = .green
    static let typeHash: Color = .orange
    static let typeSet: Color = .purple
    static let typeZSet: Color = .pink
    static let typeStream: Color = .secondary
    static let typeUnknown: Color = .secondary

    static let jsonKey: Color = .teal
    static let jsonString: Color = .green
    static let jsonNumber: Color = .blue
    static let jsonBoolean: Color = .orange
    static let jsonNull: Color = .red

    static let shellCommand: Color = .purple
    static let shellString: Color = .green
    static let shellNumber: Color = .orange
    static let shellComment: Color = .secondary

    static func expirationColor(_ label: String) -> Color {
        switch label {
        case "< 1h": return .red
        case "1-6h": return .orange
        case "6-24h": return .yellow
        case "1-7d": return .blue
        case "7-30d": return .green
        case "> 30d": return .secondary
        case "No expiry": return .gray
        default: return .secondary
        }
    }

    static func typeColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "string": return typeString
        case "list": return typeList
        case "hash": return typeHash
        case "set": return typeSet
        case "zset": return typeZSet
        case "stream": return typeStream
        default: return typeUnknown
        }
    }
}
