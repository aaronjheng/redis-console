import AppKit
import SwiftUI

// MARK: - Syntax Tokenization Protocol

/// A range of source text classified into a syntax category for highlighting.
struct SyntaxToken {
    let range: NSRange
    let type: SyntaxTokenType
}

/// Syntax categories with a stable color mapping. New languages reuse these so
/// the editor's color palette stays consistent across Lua, JavaScript, etc.
enum SyntaxTokenType {
    case keyword
    case string
    case number
    case comment
    case builtin
    case type  // language-specific "special" globals (e.g. redis, KEYS)
    case member  // API member (e.g. redis.call)
    case constant  // named constants (e.g. redis.LOG_DEBUG)

    var color: NSColor {
        switch self {
        case .keyword: NSColor(AppColor.syntaxKey)
        case .string: NSColor(AppColor.syntaxString)
        case .number: NSColor(AppColor.syntaxNumber)
        case .comment: .secondaryLabelColor
        case .builtin: NSColor(AppColor.syntaxKey)
        case .type: NSColor(AppColor.terminalPrompt)
        case .member: NSColor(AppColor.info)
        case .constant: NSColor(AppColor.chartSet)
        }
    }
}

/// Tokenizes source text into highlightable ranges. Implementations are pure
/// functions of the source: the editor calls this after every edit.
protocol SyntaxTokenizer: Sendable {
    func tokens(in text: String) -> [SyntaxToken]
}

/// Provides context-aware completions at a source location.
protocol SyntaxCompletionProvider: Sendable {
    /// `partial` is the word being typed (may be empty). `location` is the
    /// caret's absolute index into `text`.
    func completions(text: String, at location: Int, partial: String) -> [String]
}

// MARK: - Lua Tokenizer

/// Tokenizes Lua 5.1 source as written for Redis Functions.
///
/// Redis Functions run Lua 5.1 with a `redis` API surface and a few extra
/// globals (`KEYS`, `ARGV`, `cjson`, `cmsgpack`, `bit`). This is a single-pass
/// scanner that respects comments, long brackets (`[[ ]]`, `[==[ ]==]`), and
/// quoted strings so keywords inside them are never mis-highlighted.
struct LuaTokenizer: SyntaxTokenizer {
    func tokens(in text: String) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        var i = text.startIndex
        let end = text.endIndex

        // Tracks whether the immediately preceding identifier was the `redis`
        // global directly followed by `.`; lets us color `redis.call`'s member
        // as an API reference.
        var expectRedisMember = false

        while i < end {
            let c = text[i]

            if c.isWhitespace {
                expectRedisMember = false
                i = text.index(after: i)
                continue
            }

            // Shebang line: `#!lua name=...` -> comment to end of line.
            let isLineStart = i == text.startIndex || text[text.index(before: i)] == "\n"
            if isLineStart, c == "#" {
                let next = text.index(after: i)
                if next < end, text[next] == "!" {
                    var j = i
                    while j < end, text[j] != "\n" { j = text.index(after: j) }
                    tokens.append(SyntaxToken(range: NSRange(i..<j, in: text), type: .comment))
                    i = j
                    expectRedisMember = false
                    continue
                }
            }

            // Comments: `--`, `--[[ ... ]]`, `--[=*[ ... ]=*]`.
            if c == "-" {
                let next = text.index(after: i)
                if next < end, text[next] == "-" {
                    let afterDashes = text.index(after: next)
                    if let open = LuaTokenizer.matchLongBracketOpen(in: text, at: afterDashes) {
                        let close =
                            LuaTokenizer.matchLongBracketClose(
                                in: text, after: open.after, level: open.level
                            ) ?? end
                        tokens.append(SyntaxToken(range: NSRange(i..<close, in: text), type: .comment))
                        i = close
                    } else {
                        var j = afterDashes
                        while j < end, text[j] != "\n" { j = text.index(after: j) }
                        tokens.append(SyntaxToken(range: NSRange(i..<j, in: text), type: .comment))
                        i = j
                    }
                    expectRedisMember = false
                    continue
                }
                // Plain '-' (minus) -> punctuation.
                expectRedisMember = false
                i = text.index(after: i)
                continue
            }

            // Long-bracket strings: `[[ ... ]]`, `[=*[ ... ]=*]`.
            if c == "[" {
                if let open = LuaTokenizer.matchLongBracketOpen(in: text, at: i) {
                    let close =
                        LuaTokenizer.matchLongBracketClose(
                            in: text, after: open.after, level: open.level
                        ) ?? end
                    tokens.append(SyntaxToken(range: NSRange(i..<close, in: text), type: .string))
                    i = close
                    expectRedisMember = false
                    continue
                }
                expectRedisMember = false
                i = text.index(after: i)
                continue
            }

            // Short strings.
            if c == "\"" || c == "'" {
                let quote = c
                var j = text.index(after: i)
                while j < end {
                    let d = text[j]
                    if d == "\\" {
                        j = text.index(after: j)
                        if j < end { j = text.index(after: j) }
                        continue
                    }
                    if d == quote {
                        j = text.index(after: j)
                        break
                    }
                    if d == "\n" { break }  // unterminated; stop at newline
                    j = text.index(after: j)
                }
                tokens.append(SyntaxToken(range: NSRange(i..<j, in: text), type: .string))
                i = j
                expectRedisMember = false
                continue
            }

            // Numbers.
            if c.isNumber {
                var j = text.index(after: i)
                if c == "0", j < end, text[j] == "x" || text[j] == "X" {
                    j = text.index(after: j)
                    while j < end, text[j].isHexDigit { j = text.index(after: j) }
                } else {
                    while j < end, text[j].isNumber { j = text.index(after: j) }
                    let afterDot = text.index(after: j)
                    if j < end, text[j] == ".", afterDot < end, text[afterDot].isNumber {
                        j = afterDot
                        while j < end, text[j].isNumber { j = text.index(after: j) }
                    }
                    if j < end, text[j] == "e" || text[j] == "E" {
                        var k = text.index(after: j)
                        if k < end, text[k] == "+" || text[k] == "-" { k = text.index(after: k) }
                        if k < end, text[k].isNumber {
                            j = k
                            while j < end, text[j].isNumber { j = text.index(after: j) }
                        }
                    }
                }
                tokens.append(SyntaxToken(range: NSRange(i..<j, in: text), type: .number))
                i = j
                expectRedisMember = false
                continue
            }

            // Identifiers / keywords.
            if c.isLetter || c == "_" {
                var j = text.index(after: i)
                while j < end {
                    let d = text[j]
                    if d.isLetter || d.isNumber || d == "_" {
                        j = text.index(after: j)
                    } else {
                        break
                    }
                }
                let word = String(text[i..<j])
                if let type = LuaTokenizer.classify(word, member: expectRedisMember) {
                    tokens.append(SyntaxToken(range: NSRange(i..<j, in: text), type: type))
                }
                expectRedisMember = false
                i = j
                continue
            }

            // Member-access dot: enable member context only when it directly
            // follows the `redis` global.
            if c == "." {
                // Handled by tracking the previous identifier implicitly; the
                // dot itself only matters relative to `redis`, which we detect
                // when we reach the following identifier by checking the char
                // before the dot. Recompute context here.
                let prev = text.index(before: i)
                if prev >= text.startIndex {
                    // Walk back to the start of the preceding word.
                    var wordScan = prev
                    while wordScan > text.startIndex {
                        let ch = text[wordScan]
                        guard ch.isLetter || ch.isNumber || ch == "_" else { break }
                        wordScan = text.index(before: wordScan)
                    }
                    let wordStart = text.index(after: wordScan)
                    if wordStart <= prev {
                        let prevWord = String(text[wordStart...prev])
                        if prevWord == "redis", text.index(after: prev) == i {
                            expectRedisMember = true
                            i = text.index(after: i)
                            continue
                        }
                    }
                }
                expectRedisMember = false
                i = text.index(after: i)
                continue
            }

            // Any other punctuation.
            expectRedisMember = false
            i = text.index(after: i)
        }

        return tokens
    }

    // MARK: Lexical sets

    fileprivate static let keywordsSet: Set<String> = [
        "and", "break", "do", "else", "elseif", "end", "false", "for", "function",
        "if", "in", "local", "nil", "not", "or", "repeat", "return", "then",
        "true", "until", "while",
    ]
    fileprivate static let redisGlobalsSet: Set<String> = ["redis", "KEYS", "ARGV"]

    fileprivate static let redisMethodsSet: Set<String> = [
        "call", "pcall", "status_reply", "error_reply", "log", "sha1hex",
        "replicate_commands", "set_repl", "breakpoint", "register_function",
        "get_repl",
    ]
    fileprivate static let redisConstantsSet: Set<String> = [
        "LOG_DEBUG", "LOG_VERBOSE", "LOG_NOTICE", "LOG_WARNING",
        "REPL_ALL", "REPL_SLAVE", "REPL_REPLICA", "REPL_NONE", "REPL_AOF",
    ]

    fileprivate static let builtinsSet: Set<String> = [
        // Lua 5.1 base library
        "assert", "collectgarbage", "dofile", "error", "getfenv", "getmetatable",
        "ipairs", "load", "loadfile", "loadstring", "module", "next", "pairs",
        "pcall", "print", "rawequal", "rawget", "rawset", "select", "setfenv",
        "setmetatable", "tonumber", "tostring", "type", "unpack", "xpcall",
        "require",
        // standard libraries
        "coroutine", "math", "io", "os", "string", "table", "package",
        // Redis-provided
        "cjson", "cmsgpack", "bit",
    ]

    private static func classify(_ word: String, member: Bool) -> SyntaxTokenType? {
        if keywordsSet.contains(word) { return .keyword }
        if redisGlobalsSet.contains(word) { return .type }
        if member {
            if redisMethodsSet.contains(word) { return .member }
            if redisConstantsSet.contains(word) { return .constant }
            return nil
        }
        if builtinsSet.contains(word) { return .builtin }
        return nil
    }

    // MARK: Long brackets

    /// If a long-bracket opening `[[` or `[=*[` starts at `start`, returns the
    /// index just past the opening and the bracket level (count of `=`).
    private static func matchLongBracketOpen(
        in text: String, at start: String.Index
    ) -> (after: String.Index, level: Int)? {
        guard start < text.endIndex, text[start] == "[" else { return nil }
        var level = 0
        var idx = text.index(after: start)
        while idx < text.endIndex, text[idx] == "=" {
            level += 1
            idx = text.index(after: idx)
        }
        guard idx < text.endIndex, text[idx] == "[" else { return nil }
        return (text.index(after: idx), level)
    }

    /// Finds the index just past the matching `]=*]` (with the given level)
    /// searching from `start`. Returns nil if unclosed.
    private static func matchLongBracketClose(
        in text: String, after start: String.Index, level: Int
    ) -> String.Index? {
        var i = start
        while i < text.endIndex {
            guard text[i] == "]" else {
                i = text.index(after: i)
                continue
            }
            var j = text.index(after: i)
            var seen = 0
            while j < text.endIndex, text[j] == "=" {
                seen += 1
                j = text.index(after: j)
            }
            if seen == level, j < text.endIndex, text[j] == "]" {
                return text.index(after: j)
            }
            i = text.index(after: i)
        }
        return nil
    }
}

// MARK: - Lua Completion Provider

/// Offers `redis.*` members after `redis.` and general globals otherwise.
struct LuaCompletionProvider: SyntaxCompletionProvider {
    func completions(text: String, at location: Int, partial: String) -> [String] {
        if Self.isPrecededByRedisDot(text, location: location) {
            return Self.filter(Self.redisMembers, by: partial)
        }
        return Self.filter(Self.general, by: partial)
    }

    /// True when the 6 characters ending at `location` are `redis.` and they
    /// are not preceded by another word character (so `xredis.` does not match).
    static func isPrecededByRedisDot(_ text: String, location: Int) -> Bool {
        let ns = text as NSString
        guard location >= 6 else { return false }
        let before = ns.substring(with: NSRange(location: location - 6, length: 6))
        guard before == "redis." else { return false }
        if location - 7 >= 0 {
            let prev = ns.character(at: location - 7)
            if Self.isWordUnit(prev) { return false }
        }
        return true
    }

    private static let redisMembers: [String] =
        (LuaTokenizer.redisMethods.union(LuaTokenizer.redisConstants)).sorted()

    private static let general: [String] =
        (LuaTokenizer.redisGlobals.union(LuaTokenizer.builtins).union(LuaTokenizer.keywords))
        .sorted()

    private static func filter(_ list: [String], by partial: String) -> [String] {
        guard !partial.isEmpty else { return list }
        let prefix = partial.lowercased()
        return list.filter { $0.lowercased().hasPrefix(prefix) }
    }

    private static func isWordUnit(_ unit: unichar) -> Bool {
        (unit >= 48 && unit <= 57)  // 0-9
            || (unit >= 65 && unit <= 90)  // A-Z
            || (unit >= 97 && unit <= 122)  // a-z
            || unit == 95  // _
    }
}

extension LuaTokenizer {
    /// Exposes the private lexical sets to the same-file completion provider.
    fileprivate static var redisMethods: Set<String> { LuaTokenizer.redisMethodsSet }
    fileprivate static var redisConstants: Set<String> { LuaTokenizer.redisConstantsSet }
    fileprivate static var redisGlobals: Set<String> { LuaTokenizer.redisGlobalsSet }
    fileprivate static var builtins: Set<String> { LuaTokenizer.builtinsSet }
    fileprivate static var keywords: Set<String> { LuaTokenizer.keywordsSet }
}
