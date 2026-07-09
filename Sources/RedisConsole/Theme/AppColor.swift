import SwiftUI

/// Semantic color tokens used across the app.
///
/// Prefer these over raw `.red`/`.green`/`.blue` so the inventory generator and
/// future theming always render consistent, readable colors.
enum AppColor {
    // MARK: - Status

    static let success: Color = .green
    static let error: Color = .red
    static let warning: Color = .orange
    static let info: Color = .blue

    // MARK: - Backgrounds

    static let codeBackground: Color = Color(nsColor: .textBackgroundColor)
    static let controlBackground: Color = Color(nsColor: .controlBackgroundColor)
    static let subtleBackground: Color = Color.secondary.opacity(0.12)

    // MARK: - Redis type chart colors

    static let chartString: Color = .blue
    static let chartList: Color = .green
    static let chartHash: Color = .orange
    static let chartSet: Color = .purple
    static let chartZSet: Color = .pink

    // MARK: - TTL buckets

    static let ttlExpired: Color = .red
    static let ttlShort: Color = .orange
    static let ttlMedium: Color = .yellow
    static let ttlLong: Color = .blue
    static let ttlDistant: Color = .green

    // MARK: - Terminal / Shell

    static let terminalPrompt: Color = .accentColor
    static let terminalCommand: Color = .accentColor
    static let terminalSuccess: Color = .green
    static let terminalError: Color = .red
    static let terminalOutputBackground: Color = Color.secondary.opacity(0.1)

    // MARK: - Syntax highlighting

    static let syntaxKey: Color = .teal
    static let syntaxString: Color = .green
    static let syntaxNumber: Color = .orange
    static let syntaxBool: Color = .blue
    static let syntaxNull: Color = .orange
    static let syntaxPunctuation: Color = .secondary
}
