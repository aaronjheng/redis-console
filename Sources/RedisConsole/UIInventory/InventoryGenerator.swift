import AppKit
import Foundation
import SwiftUI

// MARK: - Inventory Generator

@MainActor
final class InventoryGenerator {
    let outputDirectory: URL
    let windowSize = NSSize(width: 1200, height: 800)

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    func generate() async {
        let entries = UIInventoryRegistry.sortedByPriority
        var results: [InventoryResult] = []

        let inventoryDir = outputDirectory.appendingPathComponent("ui-inventory")
        let screenshotsDir = inventoryDir.appendingPathComponent("screenshots")
        try? FileManager.default.createDirectory(at: screenshotsDir, withIntermediateDirectories: true)

        let store = AppStore.shared

        print("UI Inventory Generator")
        print("Output: \(inventoryDir.path)")
        print("Entries: \(entries.count)")
        print(String(repeating: "-", count: 60))

        for (index, entry) in entries.enumerated() {
            let counter = String(format: "%2d/%2d", index + 1, entries.count)
            print("  [\(counter)] \(entry.id) — \(entry.state)")

            let result = await captureEntry(entry, store: store)
            results.append(result)

            if result.success {
                print("         ✓ captured")
            } else {
                print("         ✗ failed: \(result.error ?? "unknown")")
            }
        }

        print(String(repeating: "-", count: 60))

        let exporter = InventoryExporter(outputDirectory: outputDirectory)
        do {
            try exporter.writeAll(results)
            let successCount = results.filter(\.success).count
            print("✓ UI Inventory generated: \(inventoryDir.path)")
            print("  \(successCount)/\(results.count) screenshots captured")
        } catch {
            print("✗ Failed to write inventory: \(error)")
        }
    }

    private func captureEntry(_ entry: any UIInventoryEntry, store: AppStore) async -> InventoryResult {
        let state = ConnectionState()
        store.connections = []

        entry.configure(state: state, store: store)
        await entry.prepare(state: state)

        let size = entry.windowSize ?? windowSize
        let rootView = TabContentView()
            .environment(state)
            .environment(store)

        let screenshotData = ScreenshotCapture.capture(rootView: rootView, size: size)

        let screenshotPath: String?
        if let data = screenshotData {
            let path = "screenshots/\(entry.id).png"
            let fileURL = inventoryDir().appendingPathComponent(path)
            try? data.write(to: fileURL)
            screenshotPath = path
        } else {
            screenshotPath = nil
        }

        return InventoryResult(
            id: entry.id,
            feature: entry.feature,
            module: entry.module,
            state: entry.state,
            priority: entry.priority,
            notes: entry.notes,
            viewHierarchy: entry.viewHierarchy,
            screenshotPath: screenshotPath,
            generatedAt: Date(),
            success: screenshotData != nil,
            error: screenshotData == nil ? "Failed to capture screenshot" : nil
        )
    }

    private func inventoryDir() -> URL {
        outputDirectory.appendingPathComponent("ui-inventory")
    }

    // MARK: - Launch Entry Point

    static func runIfNeeded() -> Bool {
        let args = CommandLine.arguments
        guard args.contains("--generate-ui-inventory") else {
            return false
        }

        let outputDir: URL
        if let outputIndex = args.firstIndex(of: "--output"),
            outputIndex + 1 < args.count {
            outputDir = URL(fileURLWithPath: args[outputIndex + 1])
        } else {
            outputDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = InventoryGeneratorDelegate(outputDirectory: outputDir)
        app.delegate = delegate
        app.run()
        return true
    }
}

// MARK: - Inventory Generator Delegate

@MainActor
final class InventoryGeneratorDelegate: NSObject, NSApplicationDelegate {
    let outputDirectory: URL

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            let generator = InventoryGenerator(outputDirectory: outputDirectory)
            await generator.generate()
            NSApplication.shared.terminate(nil)
        }
    }
}
