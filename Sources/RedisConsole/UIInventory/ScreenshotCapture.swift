import AppKit
import Foundation
import SwiftUI

// MARK: - Screenshot Capture

@MainActor
enum ScreenshotCapture {
    static func capture(
        view: some View,
        size: NSSize,
        appearance: NSAppearance = NSAppearance(named: .darkAqua) ?? .init()
    ) -> Data? {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.contentView = NSHostingView(rootView: view)
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFrontRegardless()

        window.layoutIfNeeded()
        if let hostingView = window.contentView {
            hostingView.layoutSubtreeIfNeeded()
        }

        for _ in 0..<10 {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }

        guard let hostingView = window.contentView,
            let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        else {
            window.orderOut(nil)
            return nil
        }

        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        let pngData = rep.representation(using: .png, properties: [:])

        window.orderOut(nil)
        return pngData
    }

    static func capture(
        rootView: some View,
        size: NSSize,
        appearance: NSAppearance = NSAppearance(named: .darkAqua) ?? .init()
    ) -> Data? {
        capture(view: rootView, size: size, appearance: appearance)
    }
}
