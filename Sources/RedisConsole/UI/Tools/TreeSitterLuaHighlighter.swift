import Foundation
import SwiftTreeSitter
import TreeSitterLua

// MARK: - Tree-sitter Lua Highlighter

/// Syntax highlighting backed by the tree-sitter Lua grammar.
///
/// This replaces the hand-written `LuaTokenizer` with tree-sitter's incremental
/// parser and the upstream `highlights.scm` query (vendored in
/// `Vendor/tree-sitter-lua/queries`). Tree-sitter produces a real syntax tree,
/// so highlighting is more accurate than a pure lexer (e.g. it distinguishes
/// function-call arguments from declarations, understands block structure).
///
/// Token capture names from `highlights.scm` (e.g. `keyword`, `string`,
/// `function`, `constant.builtin`) are mapped onto the app's shared
/// `SyntaxTokenType` color palette.
///
/// `Parser` and `Query` are not `Sendable`, so this class is marked
/// `@unchecked Sendable` to satisfy the `SyntaxTokenizer` protocol. Instances
/// are only ever used from the main actor (text view edits), so this is safe.
final class TreeSitterLuaHighlighter: @unchecked Sendable, SyntaxTokenizer {
    private let parser = Parser()
    private let query: Query
    private let language = Language(language: tree_sitter_lua())

    init() {
        // Load the highlights.scm query that ships with the vendored
        // TreeSitterLua package (bundled as a resource). The bundle follows
        // SPM's `TreeSitterLua_TreeSitterLua` naming convention.
        let config = try? LanguageConfiguration(language, name: "Lua", bundleName: "TreeSitterLua_TreeSitterLua")
        // Fall back to building the query from the raw scm data if the bundle
        // lookup fails (e.g. in test contexts).
        // Prefer the bundled highlights.scm (loaded via LanguageConfiguration's
        // bundle lookup); fall back to a raw file lookup, then to an empty
        // query (no highlighting) so the view never crashes on init.
        self.query = Self.makeQuery(language: language, config: config)

        try? parser.setLanguage(language)
    }

    private static func makeQuery(
        language: Language, config: LanguageConfiguration?
    ) -> Query {
        if let query = config?.queries[.highlights] {
            return query
        }
        if let url = highlightsURL, let query = try? Query(language: language, url: url) {
            return query
        }
        // swiftlint:disable:next force_try
        return try! Query(language: language, data: Data())
    }

    func tokens(in text: String) -> [SyntaxToken] {
        guard let tree = parser.parse(text) else { return [] }

        // `Query.execute(in:)` returns a `QueryCursor` that is itself a
        // `Sequence` of `QueryMatch`. The Lua highlight query does not rely on
        // #eq?/#match? predicates, so we can consume it directly.
        let cursor = query.execute(in: tree)
        let namedRanges = cursor.highlights()

        return namedRanges.compactMap { namedRange -> SyntaxToken? in
            let nsRange = namedRange.range
            guard nsRange.length > 0 else { return nil }
            guard let type = TreeSitterLuaHighlighter.mapCapture(namedRange.name) else { return nil }
            return SyntaxToken(range: nsRange, type: type)
        }
    }

    // MARK: Capture -> color mapping

    /// Maps a tree-sitter highlight capture name (possibly dot-separated, e.g.
    /// `keyword.return`, `function.builtin`, `string.special`) to the app's
    /// shared `SyntaxTokenType`. The leading component is what matters for
    /// color selection; unknown captures are dropped (rendered as default).
    private static func mapCapture(_ name: String) -> SyntaxTokenType? {
        let head = name.split(separator: ".").first.map(String.init) ?? name
        switch head {
        case "keyword", "conditional", "repeat", "keyword.function", "keyword.return":
            return .keyword
        case "string", "string.special":
            return .string
        case "number", "float":
            return .number
        case "comment":
            return .comment
        case "function", "function.call", "function.builtin", "method", "method.call":
            return .builtin
        case "constant", "constant.builtin":
            return .constant
        case "type", "type.builtin":
            return .type
        case "variable", "variable.builtin":
            return .member
        default:
            return nil
        }
    }

    // MARK: Query loading fallback

    /// Locates `highlights.scm` in the main bundle's `TreeSitterLua` resource
    /// bundle, used when `LanguageConfiguration`'s bundle lookup fails.
    private static let highlightsURL: URL? = {
        Bundle.main.url(forResource: "highlights", withExtension: "scm", subdirectory: "queries")
            ?? Bundle.main.url(forResource: "highlights", withExtension: "scm")
    }()
}
