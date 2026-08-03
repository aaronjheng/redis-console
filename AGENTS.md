# AGENTS.md

## Project Overview

Redis Console is a native macOS Redis client written in Swift, with SSH tunnel support.

## Technology Choices

- Prefer SwiftUI; use AppKit only when necessary

## Design

Design system tokens live in `Sources/RedisConsole/Theme/` (AppColor, AppFont, AppMetrics, UIComponents).

## Code Quality

- Follow `.swift-format` and `.swiftlint.yml` configurations
- Run `just lint` to check code style, `just lint-fix` to auto-fix
- Run `just format-check` to check formatting, `just format` to auto-format

## Git Workflow

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
just run

# Install to ~/Applications
just install

# Clean build artifacts
just clean


```
