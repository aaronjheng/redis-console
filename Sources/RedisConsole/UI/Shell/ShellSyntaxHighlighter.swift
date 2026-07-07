import Foundation
import SwiftUI

// MARK: - Shell Syntax Highlighter

enum ShellSyntaxHighlighter {
    private static let redisCommands: Set<String> = {
        Set([
            "PING", "ECHO", "QUIT", "AUTH", "SELECT", "SWAPDB",
            "SET", "GET", "GETDEL", "GETEX", "SETNX", "SETEX", "PSETEX", "MSET", "MGET", "MSETNX",
            "APPEND", "GETRANGE", "SETRANGE", "STRLEN", "INCR", "INCRBY", "INCRBYFLOAT", "DECR", "DECRBY",
            "DEL", "EXISTS", "EXPIRE", "EXPIREAT", "EXPIRETIME", "PEXPIRE", "PEXPIREAT", "PEXPIRETIME",
            "TTL", "PTTL", "PERSIST", "TYPE", "RENAME", "RENAMENX", "MOVE", "COPY", "SORT", "DUMP", "RESTORE",
            "KEYS", "SCAN", "RANDOMKEY", "SORT_RO",
            "HSET", "HGET", "HMSET", "HMGET", "HGETALL", "HDEL", "HEXISTS", "HKEYS", "HVALS", "HLEN",
            "HSTRLEN", "HINCRBY", "HINCRBYFLOAT", "HSETNX", "HRANDFIELD",
            "LPUSH", "RPUSH", "LPUSHX", "RPUSHX", "LPOP", "RPOP", "LLEN", "LRANGE", "LINDEX", "LSET",
            "LINSERT", "LREM", "LTRIM", "LPOS", "LMOVE", "BLMOVE", "BLPOP", "BRPOP", "BRPOPLPUSH",
            "SADD", "SREM", "SMEMBERS", "SISMEMBER", "SCARD", "SPOP", "SRANDMEMBER", "SMOVE", "SDIFF",
            "SINTER", "SUNION", "SDIFFSTORE", "SINTERSTORE", "SUNIONSTORE", "SSCAN", "SMISMEMBER",
            "ZADD", "ZREM", "ZCARD", "ZCOUNT", "ZSCORE", "ZMSCORE", "ZRANK", "ZREVRANK", "ZRANGE",
            "ZREVRANGE", "ZRANGEBYSCORE", "ZREVRANGEBYSCORE", "ZRANGEBYLEX", "ZREVRANGEBYLEX",
            "ZINCRBY", "ZINTERSTORE", "ZUNIONSTORE", "ZPOPMIN", "ZPOPMAX", "BZPOPMIN", "BZPOPMAX",
            "ZDIFF", "ZINTER", "ZUNION", "ZDIFFSTORE", "ZRANDMEMBER", "ZSCAN", "ZREMRANGEBYRANK",
            "ZREMRANGEBYSCORE", "ZREMRANGEBYLEX", "ZLEXCOUNT", "ZMPOP",
            "FLUSHDB", "FLUSHALL", "DBSIZE", "INFO", "CONFIG", "CLIENT", "SLOWLOG", "MONITOR",
            "SUBSCRIBE", "UNSUBSCRIBE", "PSUBSCRIBE", "PUNSUBSCRIBE", "PUBLISH", "PUBSUB",
            "MULTI", "EXEC", "DISCARD", "WATCH", "UNWATCH",
            "CLUSTER", "CLUSTER INFO", "CLUSTER NODES", "CLUSTER SLOTS", "CLUSTER KEYSLOT",
            "READONLY", "READWRITE", "ASKING",
            "BGREWRITEAOF", "BGSAVE", "LASTSAVE", "SAVE", "SHUTDOWN", "SLAVEOF", "REPLICAOF",
            "ROLE", "REPLCONF", "WAIT", "WAITAOF",
            "MEMORY", "MEMORY USAGE", "MEMORY STATS", "MEMORY PURGE", "MEMORY DOCTOR",
            "LATENCY", "LATENCY LATEST", "LATENCY HISTORY", "LATENCY RESET", "LATENCY GRAPH",
            "ACL", "ACL LIST", "ACL USERS", "ACL GETUSER", "ACL SETUSER", "ACL DELUSER",
            "ACL CAT", "ACL GENPASS", "ACL LOG", "ACL SAVE", "ACL LOAD", "ACL DRYRUN",
            "MODULE", "MODULE LIST", "MODULE LOAD", "MODULE UNLOAD",
            "OBJECT", "OBJECT ENCODING", "OBJECT IDLETIME", "OBJECT REFCOUNT", "OBJECT FREQ",
            "TOUCH", "UNLINK", "LOLWUT", "HELLO", "RESET", "FAILOVER",
            "EVAL", "EVALSHA", "EVAL_RO", "EVALSHA_RO", "SCRIPT", "SCRIPT LOAD", "SCRIPT FLUSH",
            "SCRIPT KILL", "SCRIPT EXISTS",
            "XADD", "XLEN", "XRANGE", "XREVRANGE", "XREAD", "XREADGROUP", "XGROUP", "XACK",
            "XCLAIM", "XAUTOCLAIM", "XDEL", "XTRIM", "XSETID", "XINFO", "XPENDING",
            "JSON.SET", "JSON.GET", "JSON.DEL", "JSON.TYPE", "JSON.NUMINCRBY", "JSON.NUMMULTBY",
            "JSON.STRAPPEND", "JSON.STRLEN", "JSON.ARRAPPEND", "JSON.ARRPOP", "JSON.ARRTRIM",
            "JSON.ARRINSERT", "JSON.ARRLEN", "JSON.OBJKEYS", "JSON.OBJLEN", "JSON.CLEAR",
            "JSON.TOGGLE", "JSON.FORGET", "JSON.RESP", "JSON.DEBUG", "JSON.MGET",
            "FT.SEARCH", "FT.AGGREGATE", "FT.CREATE", "FT.INFO", "FT.ALTER", "FT.DROPINDEX",
            "FT.ALIASADD", "FT.ALIASDEL", "FT.ALIASUPDATE", "FT.TAGVALS", "FT.SUGADD",
            "FT.SUGGET", "FT.SUGDEL", "FT.SYNUPDATE", "FT.SYNDUMP", "FT.SPELLCHECK",
            "FT.DICTADD", "FT.DICTDEL", "FT.DICTDUMP", "FT.PROFILE", "FT.CONFIG",
            "TS.CREATE", "TS.ALTER", "TS.ADD", "TS.MADD", "TS.INCRBY", "TS.DECRBY",
            "TS.GET", "TS.MGET", "TS.RANGE", "TS.MRANGE", "TS.INFO", "TS.QUERYINDEX",
            "BF.ADD", "BF.EXISTS", "BF.INFO", "BF.INSERT", "BF.MADD", "BF.MEXISTS",
            "BF.RESERVE", "BF.SCANDUMP", "BF.LOADCHUNK",
            "CMS.INITBYDIM", "CMS.INITBYPROB", "CMS.INCRBY", "CMS.QUERY", "CMS.MERGE",
            "CF.ADD", "CF.EXISTS", "CF.INFO", "CF.INSERT", "CF.EXISTS", "CF.COUNT",
            "CF.DEL", "CF.MEXISTS", "CF.RESERVE", "CF.SCANDUMP", "CF.LOADCHUNK",
            "TOPK.ADD", "TOPK.INCRBY", "TOPK.QUERY", "TOPK.COUNT", "TOPK.LIST", "TOPK.INFO",
            "TDIGEST.CREATE", "TDIGEST.ADD", "TDIGEST.MERGE", "TDIGEST.CDF", "TDIGEST.QUANTILE",
            "TDIGEST.MIN", "TDIGEST.MAX", "TDIGEST.INFO", "TDIGEST.RANK", "TDIGEST.REVRANK",
            "TDIGEST.BYRANK", "TDIGEST.BYREVRANK", "TDIGEST.TRIMMED_MEAN",
            "BITCOUNT", "BITFIELD", "BITFIELD_RO", "BITOP", "BITPOS", "GETBIT", "SETBIT",
            "GEOADD", "GEODIST", "GEOHASH", "GEOPOS", "GEORADIUS", "GEORADIUS_RO",
            "GEORADIUSBYMEMBER", "GEORADIUSBYMEMBER_RO", "GEOSEARCH", "GEOSEARCHSTORE",
            "HLLPFADD", "HLLPFCOUNT", "HLLPFMERGE",
        ])
    }()

    private static let numberPattern = try! NSRegularExpression(  // swiftlint:disable:this force_try
        pattern: #"^-?\d+(\.\d+)?([eE][+-]?\d+)?"#
    )
    private static let quotedStringPattern = try! NSRegularExpression(  // swiftlint:disable:this force_try
        pattern: #""[^"\\]*(\\.[^"\\]*)*"|'[^']*'"#
    )
    private static let commentPattern = try! NSRegularExpression(  // swiftlint:disable:this force_try
        pattern: "#.*$", options: .anchorsMatchLines
    )

    enum TokenType {
        case command
        case string
        case number
        case comment
        case `default`

        var color: Color {
            switch self {
            case .command: return AppColor.chartSet
            case .string: return AppColor.syntaxString
            case .number: return AppColor.syntaxNumber
            case .comment: return .secondary
            case .default: return .primary
            }
        }
    }

    struct Token {
        let range: NSRange
        let type: TokenType
    }

    static func highlight(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let nsRange = NSRange(text.startIndex..., in: text)

        // Highlight comments first
        commentPattern.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let range = match?.range else { return }
            guard let attrRange = Range(range, in: attributed) else { return }
            attributed[attrRange].foregroundColor = TokenType.comment.color
        }

        // Highlight quoted strings
        quotedStringPattern.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let range = match?.range else { return }
            guard let attrRange = Range(range, in: attributed) else { return }
            attributed[attrRange].foregroundColor = TokenType.string.color
        }

        // Tokenize by whitespace for commands and numbers
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        var searchStart = text.startIndex

        for word in words {
            guard !word.isEmpty else { continue }
            guard let range = text.range(of: word, range: searchStart..<text.endIndex) else {
                searchStart = text.endIndex
                continue
            }
            searchStart = range.upperBound

            let wordUpper = word.uppercased()

            if redisCommands.contains(wordUpper) {
                guard let attrRange = Range(range, in: attributed) else { continue }
                attributed[attrRange].foregroundColor = TokenType.command.color
                attributed[attrRange].font = AppFont.dataCell.bold()
            } else if numberPattern.firstMatch(in: word, range: NSRange(word.startIndex..., in: word)) != nil {
                let nsWordRange = NSRange(range, in: text)
                let isInString = isRangeInsideQuotedString(text, range: nsWordRange)
                if !isInString {
                    guard let attrRange = Range(range, in: attributed) else { continue }
                    attributed[attrRange].foregroundColor = TokenType.number.color
                }
            }
        }

        return attributed
    }

    private static func isRangeInsideQuotedString(_ text: String, range: NSRange) -> Bool {
        var inString = false
        var quoteChar: Character = "\""
        var index = text.startIndex

        while index < text.endIndex {
            let char = text[index]
            if char == "\\" {
                index = text.index(after: index)
                if index < text.endIndex {
                    index = text.index(after: index)
                }
                continue
            }
            if char == "\"" || char == "'" {
                if !inString {
                    inString = true
                    quoteChar = char
                } else if char == quoteChar {
                    inString = false
                }
            }
            if !inString {
                let pos = index
                let nsPos = NSRange(pos...pos, in: text)
                if nsPos.location >= range.location {
                    return false
                }
            }
            index = text.index(after: index)
        }
        return false
    }
}
