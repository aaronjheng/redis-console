import AppKit
import Foundation

// MARK: - Inventory Exporter

final class InventoryExporter {
    let outputDirectory: URL

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    private var inventoryDir: URL {
        outputDirectory.appendingPathComponent("ui-inventory")
    }

    func writeInventory(_ results: [InventoryResult]) throws {
        try FileManager.default.createDirectory(at: inventoryDir, withIntermediateDirectories: true)
        let report = InventoryReport(
            generatedAt: Date(),
            application: "Redis Console",
            version: "1.0.0",
            totalEntries: results.count,
            successCount: results.filter(\.success).count,
            failureCount: results.filter { !$0.success }.count,
            entries: results
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        try data.write(to: inventoryDir.appendingPathComponent("inventory.json"))
    }

    func writeSummary(_ results: [InventoryResult]) throws {
        try FileManager.default.createDirectory(at: inventoryDir, withIntermediateDirectories: true)
        var lines: [String] = []
        lines.append("# UI Inventory — Redis Console")
        lines.append("")
        let formatter = ISO8601DateFormatter()
        lines.append("Generated: \(formatter.string(from: Date()))")
        lines.append("")
        lines.append("- Total entries: \(results.count)")
        lines.append("- Successful: \(results.filter(\.success).count)")
        lines.append("- Failed: \(results.filter { !$0.success }.count)")
        lines.append("")

        let grouped = Dictionary(grouping: results, by: \.feature)
        for (feature, entries) in grouped.sorted(by: { $0.key < $1.key }) {
            lines.append("## \(feature)")
            lines.append("")
            lines.append("| ID | State | Priority | Status | Screenshot |")
            lines.append("|---|---|---|---|---|")
            for entry in entries.sorted(by: { $0.priority.sortOrder < $1.priority.sortOrder }) {
                let status = entry.success ? "OK" : "FAIL"
                let screenshot = entry.screenshotPath.map { "[view](\($0))" } ?? "—"
                lines.append("| \(entry.id) | \(entry.state) | \(entry.priority.rawValue) | \(status) | \(screenshot) |")
            }
            lines.append("")
        }

        let content = lines.joined(separator: "\n")
        try content.write(
            to: inventoryDir.appendingPathComponent("summary.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    func writeIndex(_ results: [InventoryResult]) throws {
        try FileManager.default.createDirectory(at: inventoryDir, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        let successCount = results.filter(\.success).count
        let failureCount = results.filter { !$0.success }.count
        let generated = formatter.string(from: Date())

        var html: [String] = []
        html.append("<!DOCTYPE html>")
        html.append("<html lang=\"en\">")
        html.append("<head>")
        html.append("<meta charset=\"utf-8\">")
        html.append("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">")
        html.append("<title>UI Inventory — Redis Console</title>")
        html.append("<style>")
        html.append(Self.stylesheet)
        html.append("</style>")
        html.append("</head>")
        html.append("<body>")
        html.append("<div class=\"container\">")
        html.append("<header>")
        html.append("<h1>UI Inventory — Redis Console</h1>")
        html.append(
            "<p class=\"meta\">Generated \(generated) • \(results.count) entries • \(successCount) OK • \(failureCount) failed</p>"
        )
        html.append("</header>")

        let grouped = Dictionary(grouping: results, by: \.feature)
        for (feature, entries) in grouped.sorted(by: { $0.key < $1.key }) {
            html.append("<section>")
            html.append("<h2>\(escape(feature))</h2>")
            html.append("<div class=\"grid\">")
            for entry in entries.sorted(by: { $0.priority.sortOrder < $1.priority.sortOrder }) {
                html.append(card(for: entry))
            }
            html.append("</div>")
            html.append("</section>")
        }

        html.append("</div>")
        html.append("</body>")
        html.append("</html>")

        let content = html.joined(separator: "\n")
        try content.write(
            to: inventoryDir.appendingPathComponent("index.html"),
            atomically: true,
            encoding: .utf8
        )
    }

    func writeMetadata(_ result: InventoryResult) throws {
        let dir = inventoryDir.appendingPathComponent("metadata")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(result)
        try data.write(to: dir.appendingPathComponent("\(result.id).json"))
    }

    func writeNavigation(_ results: [InventoryResult]) throws {
        let dir = inventoryDir.appendingPathComponent("navigation")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var lines: [String] = []
        lines.append("# UI Navigation Flow — Redis Console")
        lines.append("")
        let grouped = Dictionary(grouping: results, by: \.feature)
        for (feature, entries) in grouped.sorted(by: { $0.key < $1.key }) {
            lines.append("## \(feature)")
            lines.append("")
            for entry in entries.sorted(by: { $0.priority.sortOrder < $1.priority.sortOrder }) {
                lines.append("### \(entry.id)")
                lines.append("")
                lines.append("- State: \(entry.state)")
                lines.append("- Path: `\(entry.viewHierarchy)`")
                if !entry.notes.isEmpty {
                    lines.append("- Notes: \(entry.notes)")
                }
                lines.append("")
            }
        }
        let content = lines.joined(separator: "\n")
        try content.write(
            to: dir.appendingPathComponent("flow.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    func writeAll(_ results: [InventoryResult]) throws {
        try FileManager.default.createDirectory(at: inventoryDir, withIntermediateDirectories: true)
        for subdir in ["screenshots", "metadata", "navigation"] {
            try FileManager.default.createDirectory(
                at: inventoryDir.appendingPathComponent(subdir),
                withIntermediateDirectories: true
            )
        }
        try writeInventory(results)
        try writeSummary(results)
        try writeIndex(results)
        try writeNavigation(results)
        for result in results {
            try writeMetadata(result)
        }
    }

    // MARK: - HTML Helpers

    private static let stylesheet = """
        :root { color-scheme: dark; }
        * { box-sizing: border-box; }
        body {
            margin: 0;
            background: #0d1117;
            color: #c9d1d9;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
            line-height: 1.5;
        }
        .container { max-width: 1200px; margin: 0 auto; padding: 24px; }
        header h1 { margin: 0 0 4px; font-size: 24px; }
        header .meta { color: #8b949e; margin: 0 0 24px; font-size: 13px; }
        section { margin-bottom: 32px; }
        section h2 {
            border-bottom: 1px solid #2a2f37;
            padding-bottom: 8px;
            margin: 0 0 16px;
            font-size: 18px;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
            gap: 16px;
        }
        .card {
            background: #161b22;
            border: 1px solid #2a2f37;
            border-radius: 8px;
            overflow: hidden;
        }
        .card .thumb {
            width: 100%;
            height: 200px;
            object-fit: cover;
            display: block;
            background: #010409;
            border-bottom: 1px solid #2a2f37;
        }
        .card .placeholder {
            width: 100%;
            height: 200px;
            display: flex;
            align-items: center;
            justify-content: center;
            color: #484f58;
            background: #010409;
            border-bottom: 1px solid #2a2f37;
            font-size: 12px;
        }
        .card .body { padding: 12px; }
        .card h3 { margin: 0 0 4px; font-size: 14px; }
        .card .feature { color: #8b949e; font-size: 12px; margin: 0 0 8px; }
        .card .state { color: #adbac7; font-size: 12px; margin: 0 0 8px; }
        .card .notes { color: #8b949e; font-size: 12px; line-height: 1.4; }
        .badge {
            display: inline-block;
            padding: 2px 8px;
            border-radius: 4px;
            font-size: 11px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            color: var(--c);
            background: color-mix(in srgb, var(--c) 18%, transparent);
            border: 1px solid color-mix(in srgb, var(--c) 40%, transparent);
        }
        .status {
            display: inline-block;
            padding: 2px 8px;
            border-radius: 4px;
            font-size: 11px;
            font-weight: 600;
        }
        .status.ok { color: #3fb950; background: rgba(63, 185, 80, 0.12); }
        .status.fail { color: #f85149; background: rgba(248, 81, 73, 0.12); }
        """

    private func card(for entry: InventoryResult) -> String {
        var parts: [String] = []
        parts.append("<div class=\"card\">")
        if let path = entry.screenshotPath {
            parts.append("<img class=\"thumb\" src=\"\(escape(path))\" loading=\"lazy\" alt=\"\(escape(entry.id))\">")
        } else {
            parts.append("<div class=\"placeholder\">No screenshot</div>")
        }
        parts.append("<div class=\"body\">")
        parts.append("<h3>\(escape(entry.id))</h3>")
        parts.append("<p class=\"feature\">\(escape(entry.feature))</p>")
        parts.append("<p class=\"state\">\(escape(entry.state))</p>")
        parts.append("<p>")
        parts.append(badge(for: entry.priority))
        parts.append(" ")
        parts.append(status(for: entry.success))
        parts.append("</p>")
        if !entry.notes.isEmpty {
            parts.append("<p class=\"notes\">\(escape(entry.notes))</p>")
        }
        parts.append("</div>")
        parts.append("</div>")
        return parts.joined()
    }

    private func badge(for priority: ScreenshotPriority) -> String {
        let color =
            switch priority {
            case .critical: "#f85149"
            case .high: "#f76b15"
            case .medium: "#e3b341"
            case .low: "#8b949e"
            }
        return "<span class=\"badge\" style=\"--c:\(color)\">\(priority.rawValue)</span>"
    }

    private func status(for success: Bool) -> String {
        success ? "<span class=\"status ok\">OK</span>" : "<span class=\"status fail\">FAIL</span>"
    }

    private func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
