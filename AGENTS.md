# Redis Console

macOS native Redis client with SSH tunnel support, written in Swift/SwiftUI.

## Code Conventions

- Use the `@Observable` macro (macOS 14+); no `@Published` / ObservableObject, and no Combine dependency.
- UI types are annotated `@MainActor`; networking types are marked `@Sendable`.
- Concurrency primitives: `Mutex`, `actor`, `CheckedContinuation`; `DispatchQueue` is reserved for `RedisClient` I/O only.
- Errors use the unified `RedisError` enum conforming to `LocalizedError`.
- Dangerous operations on production environments require confirmation via `ProductionConfirmView` by typing a keyword.

## Git Workflow

Commit messages are a single sentence, capitalized, with no Conventional Commit prefix, e.g. `Add delete menu to connection list`.

## Build & Run

Follow the `.swift-format` and `.swiftlint.yml` configurations.

```bash
just lint          # swiftlint
just lint-fix      # swiftlint --fix
just format        # swift-format
just format-check  # swift-format lint
just build         # xcodebuild release
just run           # build + open app
just install       # build + copy to ~/Applications
just clean         # rm -rf .build
```
