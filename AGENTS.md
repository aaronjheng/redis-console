# AGENTS.md

## Project Overview

Redis Console is a native macOS Redis client written in Swift, with SSH tunnel support.

## Tech Stack

- **Language**: Swift 5.9+
- **Platform**: macOS 14+
- **UI Framework**: SwiftUI + AppKit (hybrid as needed)
- **Dependency Management**: Swift Package Manager
- **SSH**: swift-nio-ssh (local Vendor directory)
- **Code Formatting**: swift-format
- **Code Linting**: SwiftLint

## Technology Choices

- Prefer SwiftUI; use AppKit only when necessary

## Code Quality

- Follow `.swift-format` and `.swiftlint.yml` configurations
- Run `just lint` to check code style, `just lint-fix` to auto-fix

## Common Commands

```bash
# Lint
just lint

# Auto-fix
just lint-fix

# Build release and open app
just open

# Install to ~/Applications
just install
```
