# Color System

---

## Semantic Colors

These should be the default for most UI. They adapt to appearance automatically.

| Token | SwiftUI | Usage |
|---|---|---|
| `textPrimary` | `.primary` | Body text, labels |
| `textSecondary` | `.secondary` | Captions, timestamps, placeholders |
| `textTertiary` | `.tertiary` | Hints, disabled labels |
| `backgroundPrimary` | `.background` | Main backgrounds |
| `backgroundSecondary` | `.background.secondary` | Subtle panel backgrounds |
| `backgroundBar` | `.bar` | Footer bars, toolbars, input areas |
| `backgroundQuaternary` | `.quaternary` | Chips, status-pill backgrounds |
| `separator` | `.separator` | Dividers |
| `accent` | `.accentColor` / `.tint` | Selection, active controls, links |

---

## NSColor Wrappers

| Token | Value | Usage |
|---|---|---|
| `sidebarBackground` | `Color(nsColor: .controlBackgroundColor)` | Sidebars |
| `controlBackground` | `Color(nsColor: .controlBackgroundColor)` | Card internals, result backgrounds |
| `textEditorBackground` | `Color(nsColor: .textBackgroundColor)` | String editor |

---

## Domain Colors

Do not use raw `.red` / `.green` / `.blue` directly; route through semantic domain tokens.

### Status / Feedback

| Token | Color | Usage |
|---|---|---|
| `statusSuccess` | `.green` | Success, OK, dev environment |
| `statusWarning` | `.orange` | Warnings, estimates |
| `statusError` | `.red` | Errors, destructive actions, production env |
| `statusInfo` | `.blue` | Info, neutral highlights |

### Redis Data Types

Apply these consistently to key-type badges, analysis charts, and detail icons.

| Type | Color |
|---|---|
| `typeString` | `.blue` |
| `typeList` | `.green` |
| `typeHash` | `.orange` |
| `typeSet` | `.purple` |
| `typeZSet` | `.pink` |
| `typeStream` | `.secondary` |
| `typeUnknown` | `.secondary` |

### Expiration Timeline

| Range | Color |
|---|---|
| `< 1h` | `.red` |
| `1–6h` | `.orange` |
| `6–24h` | `.yellow` |
| `1–7d` | `.blue` |
| `7–30d` | `.green` |
| `> 30d` | `.secondary` |
| `No expiry` | `.gray` |

### Syntax Highlighting

Reuse the existing palettes; ensure they reference the same tokens.

| Element | JSON Color | Shell Color |
|---|---|---|
| Keys | `.teal` | — |
| Strings | `.green` | `.green` |
| Numbers | `.blue` | `.orange` |
| Booleans | `.orange` | — |
| Null | `.red` | — |
| Commands | — | `.purple` |
| Comments | — | `.secondary` |
