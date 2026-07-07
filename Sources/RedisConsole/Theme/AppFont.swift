import SwiftUI

/// Standard font tokens used across the app.
///
/// Using a single source of truth for monospaced fonts keeps data-heavy views
/// consistent and makes future size adjustments easy.
enum AppFont {
    static let monoBody = Font.system(.body, design: .monospaced)
    static let monoSubheadline = Font.system(.subheadline, design: .monospaced)
    static let monoCaption = Font.system(.caption, design: .monospaced)
    static let monoCaption2 = Font.system(.caption2, design: .monospaced)
    static let dataCell = Font.system(.body, design: .monospaced)
}
