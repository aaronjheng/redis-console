# UI Inventory Generator

## What This Is

A deterministic UI screenshot generator that renders every user-visible state of Redis Console without a real Redis server. It is **production tooling**, not a one-off script. The generator itself is the product; the screenshots are build artifacts.

The generated inventory is consumed downstream for: Design System generation, UI auditing, visual consistency review, regression testing, and product documentation.

---

## Design Principles

These principles drove every architectural decision. Future maintainers must preserve them.

### 1. The generator is the product, not the screenshots

The screenshots are build artifacts — they will be deleted and regenerated. The code that produces them is what we maintain. Never optimize for "getting today's screenshots" at the cost of generator maintainability.

### 2. Zero production code coupling

The only production code change is the 3-line `--generate-ui-inventory` guard in `App/AppLifecycle.swift`. The generator works by:
- Creating fresh `ConnectionState` instances (the app's own observable model)
- Injecting `FakeRedisSession` (conforms to the app's own `RedisSession` protocol)
- Rendering the app's own `TabContentView` in an off-screen `NSWindow`

This means the generator automatically tracks UI changes — if a view reads a new `ConnectionState` property, you just set that property in the entry's `configure()`. No production view code needs to know the generator exists.

### 3. Deterministic by design

Same input → same output. No timestamps in filenames, no random data, no time-dependent logic. `FakeRedisData.default` is a static dataset. This enables diff-based regression testing: run before and after a UI change, compare screenshots pixel-by-pixel.

### 4. ConnectionState as the single injection seam

`ConnectionState` (`State/ConnectionState.swift`) is the per-tab observable model that every view reads via `@Environment`. The generator creates a fresh `ConnectionState` per entry, populates it directly, and the views render as if they were in a real connected tab. This is the key insight that makes the generator possible without mocking the entire app stack.

### 5. FakeRedisSession as the protocol-level fake

`RedisSession` (`Redis/Client/RedisSession.swift:155`) is the protocol that abstracts standalone vs cluster Redis clients. `FakeRedisSession` conforms to it and returns canned RESP data. This means all of `ConnectionState`'s async methods (`scanKeys`, `loadServerInfo`, `fetchSlowLog`, etc.) can run against the fake without a real Redis server. If the app adds a new Redis command, add a case to `FakeRedisSession.send()`.

### 6. Registry as single source of truth

`UIInventoryRegistry.allEntries` is the complete inventory specification. Every UI state that should be captured is declared there. Adding a new state = adding one struct + one line in `allEntries`. No other code changes needed.

---

## Architecture

```
InventoryGenerator          Orchestrator: loops entries, captures, exports
├── UIInventoryRegistry     Static list of all UI states to capture (81 entries)
├── FakeRedisSession        Deterministic RedisSession fake (no real Redis)
├── ScreenshotCapture       Off-screen NSWindow → NSHostingView → PNG
└── InventoryExporter       JSON / HTML / Markdown writer
```

### Data flow per entry

```
1. InventoryGenerator creates fresh ConnectionState()
2. entry.configure(state:store:) — sets properties to produce the target UI
3. entry.prepare(state:) — optional async setup (rarely needed)
4. TabContentView().environment(state).environment(store) — root view
5. ScreenshotCapture.capture(rootView:size:) — off-screen NSWindow + PNG
6. PNG saved to ui-inventory/screenshots/<id>.png
7. InventoryResult collected
8. After all entries: InventoryExporter writes JSON, HTML, Markdown
```

### Why not a separate executable target?

The generator lives inside the app target (not a separate CLI tool) because it needs direct access to `ConnectionState`, `AppStore`, `TabContentView`, and all model types. These are internal to the app module. Extracting them into a shared library would be a large refactor with no benefit — the generator is already cleanly separated by directory (`Sources/RedisConsole/UIInventory/`) and has zero coupling to production view code beyond reading the same model types.

### Why not SwiftUI previews?

SwiftUI `#Preview` macros could capture individual views, but they:
- Don't support off-screen window capture at a fixed size
- Don't run the full `TabContentView` hierarchy (split views, AppKit bridges)
- Can't batch-capture 81 states in one run
- Don't produce structured metadata alongside screenshots

The `ScreenshotCapture` approach renders the real view hierarchy in a real `NSWindow`, which is as close to the actual app as possible without launching a full connection.

---

## File Map

| File | Responsibility |
|---|---|
| `UIInventoryTypes.swift` | `UIInventoryEntry` protocol, `ScreenshotPriority`, `InventoryResult`, `InventoryReport` |
| `FakeRedisSession.swift` | `FakeRedisData` (deterministic dataset) + `FakeRedisSession` (conforms to `RedisSession`) |
| `UIInventoryRegistry.swift` | All 81 entry structs + shared sample data helpers |
| `ScreenshotCapture.swift` | Off-screen `NSWindow` + `NSHostingView` → `NSBitmapImageRep` → PNG |
| `InventoryExporter.swift` | Writes `inventory.json`, `summary.md`, `index.html`, per-entry metadata |
| `InventoryGenerator.swift` | `@MainActor` runner + `InventoryGeneratorDelegate` (NSApplicationDelegate) |

Entry point: `App/AppLifecycle.swift` checks for `--generate-ui-inventory` launch arg before starting the normal app.

---

## How to Run

```bash
just generate-ui-inventory                    # output to ./ui-inventory/
just generate-ui-inventory /path/to/output    # custom output directory
```

Output structure:

```
ui-inventory/
    inventory.json        # structured metadata (all entries)
    summary.md            # human-readable table grouped by feature
    index.html            # browsable dark-themed screenshot gallery
    screenshots/          # PNG files, one per entry (1200×800)
    metadata/             # per-entry JSON
    navigation/           # navigation flow doc
```

---

## How to Add a New UI State

This is the most common task. Steps:

1. **Read the target view** to understand which `ConnectionState` properties it reads. Grep for `@Environment(ConnectionState.self)` in the view file, then trace the properties it references.

2. **Create a struct** conforming to `UIInventoryEntry` in `UIInventoryRegistry.swift`. Place it under the appropriate `// MARK:` section.

3. **Set the metadata fields**:
   ```swift
   let id = "my-feature-state"          // kebab-case, unique
   let feature = "Feature Module"       // group name
   let module = "MyView"                // primary view struct name
   let state = "Description of state"   // human-readable
   let priority: ScreenshotPriority = .medium  // critical/high/medium/low
   let notes = "How this state was set up"
   let viewHierarchy = "TabContentView > WorkspaceView > MyView"
   ```

4. **Implement `configure(state:store:)`**. Two patterns:

   **Disconnected** (connection hub — no `activeClient`):
   ```swift
   func configure(state: ConnectionState, store: AppStore) {
       store.connections = UIInventoryRegistry.sampleConnections
       state.rightPanel = .newConnection  // or .welcome / .editConnection(config)
   }
   ```

   **Connected** (workspace — needs `activeClient`):
   ```swift
   func configure(state: ConnectionState, store: AppStore) {
       UIInventoryRegistry.connect(state, view: .browser)
       state.keys = UIInventoryRegistry.sampleKeys
       state.keyTotalCount = UIInventoryRegistry.sampleKeys.count
       state.keyScannedCount = UIInventoryRegistry.sampleKeys.count
   }
   ```

   The `connect` helper sets `activeClient = FakeRedisSession()`, `selectedConnection`, and `currentView`. After that, populate whichever `ConnectionState` properties the target view reads.

5. **Append to `allEntries`** in the `UIInventoryRegistry` enum.

6. **Run `just generate-ui-inventory`** and check the screenshot.

### Key Integration Points

- `ConnectionState` (`State/ConnectionState.swift`) — the per-tab observable model. Read its properties to understand what each view consumes.
- `AppView` enum (`Models/Navigation.swift`) — selects workspace view: `.browser`, `.shell`, `.profiler`, `.slowLog`, `.databaseAnalysis`, `.serverInfo`.
- `RightPanel` enum (`Models/Navigation.swift`) — selects hub right panel: `.welcome`, `.newConnection`, `.editConnection(config)`.
- `TabContentView` (`UI/Root/ContentView.swift`) — root view; branches on `activeClient?.isConnected`.

---

## How to Audit for Missing States

When the app's UI changes (new view, new conditional branch, new state), run a coverage audit:

1. **Grep for all conditional UI branches**: Search every view file for `if`, `switch`, `ContentUnavailableView`, `ProgressView`, `.alert`, `.sheet`, `.popover`, `.confirmationDialog`. Each branch that produces a visually different screen is a potential entry.

2. **Compare against the registry**: List all `let id = "..."` in `UIInventoryRegistry.swift`. Every visual state found in step 1 should have a corresponding entry.

3. **Check state combinations**: A view may have multiple independent toggles (e.g., filter active × load-more visible × loading). Each visually distinct combination may warrant its own entry.

4. **Identify capturable vs non-capturable**: States driven by `ConnectionState` properties are capturable. States driven by `@State` inside a view (sheets, popovers, edit modes, test results) are NOT capturable without refactoring the view to accept bindings. Document non-capturable states in the entry's `notes` field.

5. **Add missing entries** following the "How to Add a New UI State" guide above.

### Audit heuristics

- Every `ContentUnavailableView` should have an entry
- Every `ProgressView` in a distinct location should have an entry
- Every error banner variant should have an entry
- Every enum-driven `switch` branch (e.g., `keyType` dispatching to String/Hash/List/Set/ZSet detail views) should have one entry per case
- Every picker/filter that changes the visible content should have an "active" variant
- Every "Load more" / pagination state should have an entry
- Every empty-collection state should have an entry

---

## How to Modify Fake Data

All deterministic mock data lives in `FakeRedisData.default` (in `FakeRedisSession.swift`). This is the single place to edit when you need different key values, server info, slow log entries, etc.

The `FakeRedisSession.send(_:)` method dispatches based on `args[0].uppercased()`. If the app adds a new Redis command, add a case here. Read `State/ConnectionState+<Feature>.swift` extension files to see exactly which commands each feature calls and what RESP shapes it expects.

### What FakeRedisSession must support

Read the `State/ConnectionState+*.swift` extension files to find every `client.send(...)`, `client.scan(...)`, `client.sendPipeline(...)`, and `client.totalKeyCount()` call. Each command and response shape must be handled in `FakeRedisSession.send()`. Missing commands return `.null`, which may cause silent failures (empty data, not crashes).

---

## Shared Sample Data Helpers

`UIInventoryRegistry` provides `fileprivate static` helpers that entries can reuse:

| Helper | What it provides |
|---|---|
| `connect(_:view:connection:)` | Sets up a connected state (FakeRedisSession + connection config + currentView) |
| `defaultConnection` | A `RedisConnectionConfig` for "Local Redis" |
| `sampleConnections` | 4 connections (dev, staging, prod, cluster) for the sidebar |
| `sampleKeys` | 7 `RedisKeyEntry` across all 5 types for browser views |
| `sampleNamespacedKeys` | 8 keys with `:` separators for namespace tree view |
| `sampleServerInfo` | Parsed INFO sections for ServerInfoView |
| `sampleCapabilities` | Redis modules for ServerInfoView |
| `sampleClusterInfo` / `sampleClusterNodes` | Cluster topology data |
| `sampleSlowLogEntries` | 5 `SlowLogEntry` for SlowLogView |
| `sampleShellHistory` | 3 `ShellHistoryEntry` for ShellView |
| `sampleAnalysis` | Full `DatabaseAnalysis` for DatabaseAnalysisView |

When adding entries that need new sample data, prefer adding a `fileprivate static` helper to `UIInventoryRegistry` rather than inlining data in the entry struct. This keeps entries concise and data reusable.

---

## Conventions

- **Deterministic**: No timestamps in filenames, no random data. `FakeRedisData` is a static dataset. Same input → same output.
- **No production changes**: The only production code modification is the 3-line `--generate-ui-inventory` guard in `App/AppLifecycle.swift`. All generator code lives under `Sources/RedisConsole/UIInventory/`.
- **File-scoped types**: Entry structs are `private` to `UIInventoryRegistry.swift`. Helpers are `fileprivate static`.
- **Swift 6 strict concurrency**: `UIInventoryEntry` protocol is `@MainActor`. `ScreenshotCapture` is `@MainActor`. `FakeRedisSession` is `@unchecked Sendable`.
- **No external dependencies**: Uses only AppKit, SwiftUI, Foundation. No SwiftSyntax or other packages.
- **Lint/format**: `just lint` and `just format` automatically cover `Sources/` recursively, including this directory.
- **Priority levels**: `critical` (core flows), `high` (important user-facing states), `medium` (secondary states/variants), `low` (edge cases, error states, empty collections).

---

## Adding New Files to the Xcode Project

The project uses explicit file references in `project.pbxproj` (not folder synchronization). If you add a new `.swift` file to this directory, you must also add it to the Xcode project:

1. In Xcode: drag the file into the `UIInventory` group under the `RedisConsole` target.
2. Or use `plistlib` in Python to add `PBXFileReference` + `PBXBuildFile` entries to `project.pbxproj` (see the pattern used for the initial 6 files).

---

## Limitations and Future Work

### Sheets and popovers (not capturable)

SwiftUI sheets/popovers are triggered by `@State` bools inside views, not `ConnectionState`. Entries for these states configure the underlying view and note the limitation in `notes`. To capture a sheet, you would need to add a `@State` binding or use `@Previewable` — not currently implemented.

Affected states: string edit mode, connection test result, shell completion suggestions, profiler filter/auto-scroll/hide-noise toggles, profiler selected entry, server info topology toggle, browser namespace expansion, non-production delete confirmation, TTL editor popover error, auto-refresh interval label.

### Appearance

Screenshots use `NSAppearance(named: .darkAqua)`. To capture light mode, modify the `appearance` parameter in `ScreenshotCapture.capture()` or add a parallel set of entries with light appearance.

### Window size

Default is 1200×800 (matching the app). Override via `windowSize` in an entry. No responsive breakpoints are captured.

### Async settling

`ScreenshotCapture` spins the runloop 10×50ms for SwiftUI to settle. If views show empty content, increase the count or duration in `ScreenshotCapture.swift`.

### System UI (not capturable)

The macOS About panel, menu bar, `NSSavePanel`/`NSOpenPanel`, and context menus are not SwiftUI views and cannot be captured by the current approach.

---

## Evolution Guide

### When the app adds a new feature module

1. Add sample data to `FakeRedisData.default` (if new Redis commands are needed)
2. Add command handling to `FakeRedisSession.send()` (if new commands)
3. Add `fileprivate static` sample data helpers to `UIInventoryRegistry`
4. Create entry structs for every visual state of the new feature
5. Append entries to `allEntries`
6. Run `just generate-ui-inventory` and verify

### When a view's conditional branches change

1. Audit the view for new branches (see "How to Audit for Missing States")
2. Add entries for any new visually distinct states
3. If a branch was removed, delete the corresponding entry

### When ConnectionState gains new properties

1. Check if any existing entry should set the new property to show a different state
2. Add new entries as needed
3. No changes to the generator infrastructure — it already creates fresh `ConnectionState` per entry

### When the app's architecture changes

The generator depends on these architectural facts:
- `ConnectionState` is `@Observable` and injected via `.environment()`
- `TabContentView` is the root view
- `RedisSession` is the protocol for Redis clients
- `AppStore.shared` holds connection definitions

If any of these change, the generator must be updated accordingly. The most likely scenario is migrating to `NavigationSplitView` or `NavigationStack` — in that case, the navigation model changes from `ConnectionState.currentView` to SwiftUI's navigation path, and entries would need to set up the path instead.

### When adding light mode support

Add a `appearance` parameter to `UIInventoryEntry` (default `.darkAqua`), then either:
- Duplicate all entries with `.lightAqua` appearance, or
- Run the generator twice with different appearance settings and merge results

### When adding CI integration

The generator already runs non-interactively (`.accessory` activation policy, auto-terminates after completion). To integrate into CI:
1. Build the app: `just build-release`
2. Run: `RedisConsole.app/Contents/MacOS/RedisConsole --generate-ui-inventory --output ci-output/`
3. Upload `ui-inventory/` as a CI artifact
4. Optionally diff screenshots against a baseline for regression detection
