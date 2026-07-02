# Layout Guidelines

---

## Three-Panel Workspace

```
┌─────────────────┬──────────────────────┬─────────────────┐
│  Tabs/Sidebar   │     Main Content     │  Detail/Form    │
│   220–280pt     │      remaining       │    ≥400pt       │
└─────────────────┴──────────────────────┴─────────────────┘
```

- Sidebars use `sidebarBackground`.
- Main content and detail panels use the default window background.
- Footer bars sit at the bottom of the main content or detail panel. Use `WorkspaceFooterBar` consistently — currently missing from DatabaseAnalysisView, ShellView, and ServerInfoView.

---

## Header Rhythm

Standardize headers across views:

```swift
VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
    Text(title).font(.headline)
    if let subtitle {
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
    }
}
.padding([.horizontal, .top], AppTheme.spacing)
```

- Left-align all headers.
- Use `.headline` for view titles.
- Use `.caption` + `.secondary` for subtitles.

**Compliance:** ServerInfoView, DatabaseAnalysisView, SlowLogView, ProfilerView, and ShellView currently use `.padding()` (SwiftUI default, ~16pt) instead of the standard `AppTheme.spacing` (8pt). These should be updated to match the standard header padding.
