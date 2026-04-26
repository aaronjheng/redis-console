# AGENTS.md

## Project Overview

Redis Console is a native macOS Redis client written in Swift, with SSH tunnel support.

## Tech Stack

- **Language**: Swift 6.3+
- **Platform**: macOS 26+
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
- Run `just format-check` to check formatting, `just format` to auto-format

## Git Workflow

- Never run `git commit`, `git push`, or other git mutations unless explicitly instructed
- If explicitly instructed to commit or push, execute directly without extra confirmation
- Commit message rules:
  - One sentence only
  - No Conventional Commit prefixes
  - Capitalize the first letter
  - Example: "Add delete menu to connection list"

## Common Commands

```bash
# Lint
just lint

# Auto-fix linting issues
just lint-fix

# Format code
just format

# Check formatting
just format-check

# Build release
just build-release

# Build release and open app
just open

# Install to ~/Applications
just install

# Clean build artifacts
just clean
```
