---
name: ui-inventory-audit
description: Use when the user wants to audit a UI Inventory, identify inconsistencies, and review coverage. Triggered by phrases like "UI audit", "audit inventory", "analyze screenshots", or when working with ui-inventory assets.
---

# UI Inventory Audit Skill

This skill turns a generated UI Inventory into a structured UI Audit report. It is designed for macOS/SwiftUI projects that already have a deterministic screenshot generator (like Redis Console's `Sources/RedisConsole/UIInventory/`), but the workflow is generic enough to adapt to other stacks.

## When to use

- The user asks for a UI audit or coverage review.
- There is an existing `ui-inventory/` directory with screenshots and metadata.
- The user wants to compare screenshots against codebase style definitions.

## Prerequisites

- A generated UI Inventory exists (screenshots + metadata + summary).
- The codebase is accessible so style definitions can be audited.
- `just generate-ui-inventory` or an equivalent command is available.

## Workflow

### Step 1 — Verify the inventory is complete

1. Check `ui-inventory/screenshots/` for PNG files.
2. If screenshots are missing or stale, run the generator:
   ```bash
   just generate-ui-inventory
   ```
3. If the generator reports success but screenshots are missing, inspect `InventoryGenerator` (or equivalent) for path mismatches between the screenshot write location and the metadata/exporter output directory.

### Step 2 — Launch parallel audits

Delegate to three subagents in parallel. Each subagent should return a structured report and must not modify files.

#### Subagent A: Codebase Style Audit

Prompt:
> Analyze the codebase for all style definitions: colors, fonts, spacing, corner radii, buttons, tables, lists, sheets, popovers, dialogs, cards, badges, banners, and empty states. Return exact file paths, line numbers, color values, and a list of inconsistencies or hardcoded values that should be centralized.

#### Subagent B: Inventory Metadata Audit

Prompt:
> Read `inventory.json`, `summary.md`, and the inventory registry/source file. Identify redundant entries, missing coverage, priority misclassifications, naming inconsistencies, and non-capturable states. Return a prioritized cleanup list.

#### Subagent C: Visual Screenshot Audit

Prompt:
> Sample screenshots across all feature groups and priorities. Focus on critical entries, error/safety states, empty/loading states, and at least one representative per feature. Identify visual inconsistencies, truncated text, missing dialogs/sheets, redundant visuals, and component drift. Return findings with screenshot IDs and a P0/P1/P2 priority order.

### Step 3 — Synthesize findings

The audit produces one artifact:

1. **UI Audit report (intermediate, do not commit)**
   - Combine the three subagent reports into a one-time audit summary.
   - Output to `ui-inventory/UI_AUDIT.md` or a temporary location.
   - This document is intentionally disposable: re-run the workflow and the audit changes.
   - Include: methodology, P0/P1/P2 findings, missing coverage, and proposed cleanup actions.

### Step 4 — Update the generator if needed

If the audit reveals capture bugs (e.g., screenshots not saved, dialogs not captured):

1. Fix the generator code.
2. Re-run the generator.
3. Re-sample affected screenshots to confirm.
4. Mention the fix in the intermediate UI Audit report.

### Step 5 — Save this workflow as a skill

If the project does not already have this skill, create:

```
.agents/skills/ui-inventory-audit/SKILL.md
```

Use this file as the template. Customize the generator command and file paths to match the project.

## Output conventions

- `UI_AUDIT.md` is an intermediate, disposable artifact. Generate it inside `ui-inventory/` (a build artifact) or a temp directory; do not commit it.
- Keep findings specific: reference screenshot IDs, file paths, and line numbers where possible.
- Prioritize safety-critical UI (production confirmations, destructive actions) over cosmetic polish.

## Example commands

```bash
# Regenerate the inventory
just generate-ui-inventory

# Verify screenshots exist
find ui-inventory/screenshots -name "*.png" | wc -l

# Check for the latest summary
cat ui-inventory/summary.md
```

## Extension ideas

- Add a fourth subagent to diff two inventory runs for regression analysis.

- Add a `capturable: Bool` field to inventory metadata for non-capturable states.
- Automate the workflow with a `just audit-ui-inventory` command.
