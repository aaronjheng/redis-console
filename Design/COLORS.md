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

Use the `AppTheme` wrappers instead of raw `Color(nsColor:)` calls.

| Token | Value | Usage |
|---|---|---|
| `sidebarBackground` | `Color(nsColor: .controlBackgroundColor)` | Sidebars |
| `controlBackground` | `Color(nsColor: .controlBackgroundColor)` | Card internals, result backgrounds |
| `textEditorBackground` | `Color(nsColor: .textBackgroundColor)` | String editor, shell results |

**Rule:** Always use `AppTheme.controlBackground` and `AppTheme.textEditorBackground` instead of writing `Color(nsColor: .controlBackgroundColor)` or `Color(nsColor: .textBackgroundColor)` directly. These are duplicated in `ServerInfoView`, `DatabaseAnalysisView`, `ShellView`, `StringDetailView`, and `ProfilerView` — replace all occurrences.

---

## Domain Colors

Do not use raw `.red` / `.green` / `.blue` directly; route through semantic domain tokens.

### Status / Feedback

| Token | Color | Usage |
|---|---|---|
| `statusSuccess` | `.green` | Success, OK, dev environment |
| `statusWarning` | `.orange` | Warnings, estimates, TTL expiry |
| `statusError` | `.red` | Errors, destructive actions, production env |
| `statusInfo` | `.blue` | Info, neutral highlights, cluster nodes |

### Warning Background

| Token | Value | Usage |
|---|---|---|
| `warningBackground` | `DomainColor.statusWarning.opacity(0.12)` | Warning banner and badge backgrounds |

Use `warningBackground` consistently — do not mix `opacity(0.1)` and `opacity(0.12)`.

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

### Cluster Topology

| Token | Color | Usage |
|---|---|---|
| `clusterNode` | `DomainColor.statusInfo` (`.blue`) | Primary cluster node indicators |
| `clusterLine` | `Color.blue.opacity(0.4)` | Topology connection lines |

Use these instead of raw `.blue` in `ClusterTopologyView`.

### Slow Log Severity

| Token | Color | Usage |
|---|---|---|
| `slowLogLow` | `.secondary` | Sub-millisecond / fast commands |
| `slowLogMedium` | `DomainColor.statusWarning` (`.orange`) | Moderate latency |
| `slowLogHigh` | `DomainColor.statusError` (`.red`) | High latency commands |

Use these instead of raw `.yellow` in `SlowLogView`.

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
