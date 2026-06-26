# Design Tokens

Use `AppTheme` constants and replace hardcoded literals gradually.

---

## Spacing

| Token | Value | Usage |
|---|---|---|
| `spacingSmall` | `4` | Tight row spacing, badge vertical padding |
| `spacing` | `8` | Standard section padding, HStack spacing |
| `spacingLarge` | `16` | Grid gaps, form padding |
| `spacingXLarge` | `20` | Large section spacing |

---

## Corner Radius

| Token | Value | Usage |
|---|---|---|
| `cornerRadiusSmall` | `4` | Badges, chips, small buttons |
| `cornerRadiusMedium` | `6` | Cards, panels, text fields |
| `cornerRadiusLarge` | `8` | Outer analysis cards, sheets |

Add `cornerRadiusLarge = 8` to `AppTheme` to replace the ad-hoc `8` values in `DatabaseAnalysisView`.

---

## Typography

Prefer SwiftUI text styles. Use custom sizes only for fixed-size controls.

| Style | Usage |
|---|---|
| `.largeTitle` | Hero icons only (e.g., production warning) |
| `.title` / `.title2` | Welcome titles, sheet headers |
| `.title3` | Key names, connection names, section headers |
| `.headline` | View titles, form section headers |
| `.subheadline` | Metadata rows, card titles |
| `.body` | Primary content, list rows |
| `.caption` | Footers, timestamps, labels |
| `.caption2` | Smallest labels, counts, node host |
| `.system(size: 11/12, weight: .medium)` | **Deprecated** — replace with `.caption` / `.caption2` |
| `.monospaced` / `.monospacedDigit()` | Code, IDs, durations, counts |

---

## Sizing

| Token | Value | Usage |
|---|---|---|
| `tabBarHeight` | `32` | Tab bar |
| `workspaceFooterHeight` | `34` | Footer bars |
| `refreshControlHeight` | `22` | Refresh/auto-refresh controls |
| `refreshButtonSize` | `26 × 22` | Refresh buttons |
| `badgeMinWidth` | `42` | Loading badge placeholder |
| `sidebarMinWidth` | `220` | Connection/workspace sidebars |
| `sidebarMaxWidth` | `280` | Connection/workspace sidebars |
| `detailPanelMinWidth` | `400` | Connection detail / value editor |
