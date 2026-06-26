# Redis Console Design System

**Version:** 1.0  
**Date:** 2026-06-26  
**Platform:** macOS 26+  
**Framework:** SwiftUI 6+ with AppKit bridges

---

## Principles

1. **Native first.** Lean on SwiftUI semantic colors and system components; avoid custom drawings unless necessary.
2. **Dark by default.** The app ships in dark mode. Light mode may be added later; all tokens should adapt via `Color` semantics or `NSColor` wrappers.
3. **Density over decoration.** Redis Console is a developer tool. Prioritize information density, clear hierarchy, and fast scanning.
4. **One component, one behavior.** Reuse the same component for the same conceptual pattern (e.g., one error banner, one loading spinner, one empty-state view).

---

## Documents

| Document | Contents |
|---|---|
| [`TOKENS.md`](TOKENS.md) | Spacing, corner radii, typography, sizing |
| [`COLORS.md`](COLORS.md) | Semantic colors, NSColor wrappers, domain color palettes |
| [`COMPONENTS.md`](COMPONENTS.md) | Buttons, badges, banners, tables, empty states, loading, cards, sheets, popovers |
| [`LAYOUT.md`](LAYOUT.md) | Three-panel workspace, header rhythm |
