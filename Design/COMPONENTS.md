# Components

---

## Button Styles

### `ToolbarIconButton`

Icon-only borderless button for toolbars.

```swift
Button(label, systemImage: icon) { action() }
    .labelStyle(.iconOnly)
    .buttonStyle(.borderless)
```

**Usage:** Browser, Detail, Server Info, Profiler, Analysis toolbars.  
**Future:** Wrap in a custom `ButtonStyle` or view modifier to centralize `.help`, `.foregroundStyle`, and hover behavior.

### `PrimaryButton`

Main action in forms and sheets.

```swift
Button(title) { action() }
    .buttonStyle(.borderedProminent)
```

**Usage:** Connect, Save, Start Profiler.

### `SecondaryButton`

Cancel / dismiss actions.

```swift
Button(title) { action() }
    .buttonStyle(.bordered)
    .role(.cancel) // when canceling
```

### `DangerIconButton`

Destructive icon-only action. Already exists as `DeleteIconButton` in `AppTheme.swift`.

```swift
DeleteIconButton(action: {}, helpText: "Delete key")
```

---

## Badge

Use the existing `Badge` view in `AppTheme.swift`.

```swift
Badge(
    text: "Production",
    systemImage: "exclamationmark.triangle.fill",
    foregroundColor: .red,
    backgroundColor: .red.opacity(0.12)
)
```

**Variants to add:**
- `EnvironmentBadge(environment:)`
- `ConnectionModeBadge(mode:)`
- `KeyTypeBadge(type:)` — uses the type-color tokens in `COLORS.md`
- `StatusBadge(status:)`

---

## Error Banner

Use the existing `ErrorBanner` view in `AppTheme.swift`. Supports `.error` and `.warning` severity, with optional dismiss action.

```swift
ErrorBanner(message: "Connection failed", dismissAction: { dismiss() })
ErrorBanner(message: "MONITOR can slow busy servers", severity: .warning)
```

**Applied in:** BrowserView (connection error), KeyDetailView (detail error), DatabaseAnalysisView (analysis error), ProfilerView (warning banner).

---

## Loading State

Use the existing `LoadingState` view in `AppTheme.swift`.

```swift
LoadingState(message: "Loading value...")
```

**Applied in:** KeyDetailView, DatabaseAnalysisView.

**For inline loading** (e.g., slow log refresh, scanning keys), use `ProgressView().controlSize(.small)` directly.

---

## Empty State

**Status: `[not implemented]`** — not yet extracted as a shared component.

Currently each view uses inline `ContentUnavailableView` directly. This is acceptable for now since each empty state has unique layout (button placement, spacing). Extract only when a consistent pattern emerges across 3+ views.

**Views using inline empty states:** BrowserView (2), KeyDetailView, ProfilerView (3), ServerInfoView, SlowLogView, ShellView, DatabaseAnalysisView.

---

## Footer Bar

Use `WorkspaceFooterBar` and `StatusFooterView` from `AppTheme.swift`.

**Rules:**
- Height is fixed at `workspaceFooterHeight` (34).
- Font is `.caption`.
- Text must not truncate; use compact formats or allow wrapping.

---

## Tables

Use SwiftUI `Table` with consistent styling.

```swift
Table(of: Row.self, selection: $selection) { ... }
    .tableStyle(.inset) // or .plain for detail tables
```

**Rules:**
- Use `.monospacedDigit()` for numeric columns.
- Keep action columns (Edit/Delete) at the trailing edge with consistent widths.
- Add `.help` to icon-only action buttons.

---

## Cards / Panels

Use the existing `Card` view in `AppTheme.swift` for dashboard-style sections.

```swift
Card(title: "Type Distribution") {
    // content
}
```

**Applied in:** DatabaseAnalysisView (type distribution, top keys, expiration timeline).

**Rules:**
- Title uses `.headline` automatically.
- Content is left-aligned with standard card padding.
- Background uses `.bar` with `cornerRadiusLarge`.

---

## Sheets and Popovers

**Sheet:** Use for multi-field creation or safety confirmations.
- Add-key sheet
- Add field/member sheets
- Production delete confirmation

**Popover:** Use for single-field edits that benefit from contextual anchoring.
- TTL editor

**Form style:** Use `.formStyle(.grouped)` for all sheets.  
**Sizing:** Use `.presentationSizing(.form)` for consistent sheet widths.

---

## Refresh Control

Unify `KeyRefreshControl` and `SlowLogRefreshControl` into one component.

```swift
struct RefreshControl: View {
    let isLoading: Bool
    let interval: TimeInterval?
    let action: () -> Void
    let onIntervalChange: (TimeInterval?) -> Void
    // ...
}
```

**Rules:**
- Height 22pt.
- Refresh button 26×22pt.
- Interval label uses `.caption2`.
- Disable/hide refresh while loading.
