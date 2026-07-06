# Redis Console

Native macOS Redis GUI client built with Swift and SwiftUI.

## Features

- **Standalone & Cluster** — full support for both deployment modes with automatic topology discovery, hash-slot routing, and MOVED/ASK redirect handling
- **SSH Tunneling** — connect to Redis instances behind firewalls via SSH (password or key-based auth, Ed25519/ECDSA)
- **TLS / mTLS** — secure connections with optional CA, client cert, and client key
- **Key Browser** — scan, filter, and manage keys with flat list or namespace tree views; inline TTL editing and deletion
- **Type-Aware Value Editor** — dedicated viewers for strings (with JSON/hex/base64/gzip formatting), hashes, lists, sets, and sorted sets; inline editing and batch operations
- **Interactive Shell** — Redis CLI with syntax highlighting, command auto-complete, dangerous-command detection, and history navigation
- **Command Profiler** — live MONITOR-based command capture with filtering and noise suppression
- **Slow Log** — query slow log entries with auto-refresh and duration color-coding
- **Database Analysis** — statistical overview of key counts, memory usage, type distribution, top keys, and namespace breakdown
- **Server Info** — structured INFO output with cluster topology visualization
- **Connection Management** — import/export connections, environment tagging (development/production), credential storage via macOS Keychain
- **Multi-Tab** — tabbed window interface with keyboard shortcuts (⌘T, ⌘W, ⌘1–9)
- **RESP2 & RESP3** — automatic protocol negotiation with RESP3 fallback

## Requirements

- macOS 26+
- Xcode 26+
- [just](https://github.com/casey/just)
- [SwiftLint](https://github.com/realm/SwiftLint)

## Build & Run

```bash
# Build and open the app
just run

# Build release only
just build-release

# Install to ~/Applications
just install
```

## Development

```bash
# Lint
just lint
just lint-fix

# Format
just format
just format-check

# Clean build artifacts
just clean
```

## Project Structure

```
Sources/RedisConsole/
├── App/                  # App entry point, lifecycle, tab management, appearance
├── Models/               # Pure data models, organized by domain
│   ├── Connection/       #   Connection, SSH, TLS configuration
│   ├── Browser/          #   Key entries, database analysis
│   ├── Shell/            #   Shell history
│   ├── SlowLog/          #   Slow log entries
│   └── Profiler/         #   Profiler captures and entries
├── State/                # Observable state (ConnectionState + extensions, AppStore)
├── Theme/                # Design tokens, color palette, reusable UI components
├── Redis/                # Redis protocol layer
│   ├── RESP/             #   RESP2/RESP3 parser and encoder
│   ├── Client/           #   Standalone & cluster clients, session protocol
│   └── Monitor/          #   MONITOR command streaming client
├── SSH/                  # SSH tunnel, cluster tunnel manager, key parsing, NIO handlers
├── Infrastructure/       # Keychain store, async timeout utility
├── UI/                   # SwiftUI views, organized by feature
│   ├── Root/             #   Top-level content view and navigation
│   ├── Connection/       #   Connection hub (list, edit, import/export)
│   ├── Workspace/        #   Connected workspace sidebar
│   ├── Browser/          #   Key browser, key detail, edit sheets
│   ├── KeyDetail/        #   Type-specific value viewers (string/hash/list/set/zset)
│   ├── Shell/            #   CLI shell view and syntax highlighter
│   └── Tools/            #   Profiler, slow log, database analysis, server info, cluster topology
├── UIInventory/          # Deterministic screenshot generator for UI states
└── Design/               # Design system documentation (tokens, colors, components, layout)
```

## Tech Stack

- **Language**: Swift 6.3+
- **UI Framework**: SwiftUI + AppKit (hybrid as needed)
- **SSH**: [swift-nio-ssh](https://github.com/apple/swift-nio-ssh) (vendored)
- **Code Formatting**: swift-format
- **Code Linting**: SwiftLint

## License

Redis Console is licensed under the [BSD-3-Clause License](https://opensource.org/licenses/BSD-3-Clause). See [LICENSE](LICENSE) for more details.
