import AppKit
import Foundation
import SwiftUI

// MARK: - Screenshot Priority

enum ScreenshotPriority: String, Codable, CaseIterable {
    case critical
    case high
    case medium
    case low

    var sortOrder: Int {
        switch self {
        case .critical: 0
        case .high: 1
        case .medium: 2
        case .low: 3
        }
    }
}

// MARK: - UI Inventory Entry Protocol

@MainActor
protocol UIInventoryEntry {
    var id: String { get }
    var feature: String { get }
    var module: String { get }
    var state: String { get }
    var priority: ScreenshotPriority { get }
    var notes: String { get }
    var viewHierarchy: String { get }
    var windowSize: NSSize? { get }

    func configure(state: ConnectionState, store: AppStore)
    func prepare(state: ConnectionState) async
}

extension UIInventoryEntry {
    var windowSize: NSSize? { nil }
    func prepare(state: ConnectionState) async {}
}

// MARK: - Inventory Result

struct InventoryResult: Codable {
    let id: String
    let feature: String
    let module: String
    let state: String
    let priority: ScreenshotPriority
    let notes: String
    let viewHierarchy: String
    let screenshotPath: String?
    let generatedAt: Date
    let success: Bool
    let error: String?
}

// MARK: - Inventory Report

struct InventoryReport: Codable {
    let generatedAt: Date
    let application: String
    let version: String
    let totalEntries: Int
    let successCount: Int
    let failureCount: Int
    let entries: [InventoryResult]
}
