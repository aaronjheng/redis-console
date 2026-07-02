# Design Tokens

Use `AppTheme` constants and replace hardcoded literals gradually.

---

## Spacing

| Token | Value | Usage |
|---|---|---|
| `spacingXSmall` | `2` | Ultra-tight HStack/VStack spacing, metadata row gaps |
| `spacingSmall` | `4` | Tight row spacing, badge vertical padding |
| `spacingSmallMedium` | `6` | Badge horizontal padding, refresh interval labels, chip padding |
| `spacing` | `8` | Standard section padding, HStack spacing |
| `spacingMedium` | `10` | Profiler entry rows, key detail metadata |
| `spacingLargeMedium` | `12` | Server info stat grid, profiler detail rows |
| `spacingLarge` | `16` | Grid gaps, form padding |
| `spacingXLarge` | `20` | Large section spacing |

---

## Corner Radius

| Token | Value | Usage |
|---|---|---|
| `cornerRadiusSmall` | `4` | Badges, chips, small buttons |
| `cornerRadiusMedium` | `6` | Cards, panels, text fields, refresh control containers |
| `cornerRadiusLarge` | `8` | Outer analysis cards, sheets |

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
| `.caption` | Footers, timestamps, labels, refresh controls |
| `.caption2` | Smallest labels, counts, node host, refresh interval labels |
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
| `refreshSeparatorSize` | `0.5 × 14` | Separator between refresh button and interval menu |
| `refreshMenuPlaceholderWidth` | `18` | Width placeholder for interval menu when hidden |
| `badgeMinWidth` | `42` | Loading badge placeholder |
| `sidebarMinWidth` | `220` | Connection/workspace sidebars |
| `sidebarMaxWidth` | `280` | Connection/workspace sidebars |
| `detailPanelMinWidth` | `400` | Connection detail / value editor |

---

## Interaction State Colors

| Token | Value | Usage |
|---|---|---|
| `hoverHighlight` | `Color.primary.opacity(0.08)` | Hover background on clickable rows, menu items |
| `selectedRowBackground` | `Color.accentColor.opacity(0.14)` | Selected row in lists, cluster node highlight |

Use these tokens instead of repeating raw `Color.primary.opacity(0.08)` or `Color.accentColor.opacity(0.14)` inline.
