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

Create a new `ErrorBanner` component.

```swift
struct ErrorBanner: View {
    let message: String
    var body: some View {
        HStack(spacing: AppTheme.spacing) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
            Spacer()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.red)
        .padding(AppTheme.spacing)
        .background(.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
    }
}
```

**Apply to:** `browser-error`, `detail-error`, `analysis-error`, `profiler-error`, `shell-danger`.

---

## Loading State

Create a `LoadingOverlay` or `LoadingState` component.

```swift
struct LoadingState: View {
    let message: String
    var body: some View {
        VStack(spacing: AppTheme.spacing) {
            ProgressView()
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(AppTheme.spacingLarge)
    }
}
```

**Rules:**
- Center in the active panel.
- Use the same spinner everywhere.
- For inline loading (e.g., slow log refresh), dim the control and show a small spinner.

---

## Empty State

Create a reusable `EmptyState` component.

```swift
struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String?
    var body: some View {
        ContentUnavailableView {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
        } description: {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

**Rules:**
- Use system SF Symbols unless a custom icon is clearly needed.
- Keep icon size consistent (48pt).
- Use the same title/subtitle style everywhere.

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

Create a `Card` component for dashboard-style views.

```swift
struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            Text(title).font(.headline)
            content
        }
        .padding(AppTheme.spacingLarge)
        .background(.bar)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge))
    }
}
```

**Usage:** `DatabaseAnalysisView`, `ProfilerView` summary, `ServerInfoView` cluster summary.

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
