import AppKit
import Observation
import SwiftUI

// MARK: - Tab Manager

@MainActor
@Observable
class TabManager {
    var tabStates: [ConnectionState] = []

    func createTab() -> ConnectionState {
        let state = ConnectionState()
        tabStates.append(state)
        return state
    }

    func closeTab(_ state: ConnectionState) {
        state.disconnect()
        tabStates.removeAll { $0.id == state.id }
    }

    func tabIndex(for state: ConnectionState) -> Int? {
        tabStates.firstIndex(where: { $0.id == state.id })
    }
}

// MARK: - Window Delegate Manager

@MainActor
final class WindowDelegateManager {
    private var delegates: [ObjectIdentifier: WindowDelegate] = [:]
    private let lock = NSLock()

    func setDelegate(_ delegate: WindowDelegate, for window: NSWindow) {
        let id = ObjectIdentifier(window)
        lock.lock()
        defer { lock.unlock() }
        delegates[id] = delegate
    }

    func removeDelegate(for window: NSWindow) {
        let id = ObjectIdentifier(window)
        lock.lock()
        defer { lock.unlock() }
        delegates.removeValue(forKey: id)
    }
}

// MARK: - Appearance Preference

enum AppAppearance: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2

    private static let userDefaultsKey = "com.redisconsole.appearance"

    var name: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    static var current: AppAppearance {
        let raw = UserDefaults.standard.integer(forKey: userDefaultsKey)
        return AppAppearance(rawValue: raw) ?? .system
    }

    @MainActor
    func apply() {
        UserDefaults.standard.set(rawValue, forKey: Self.userDefaultsKey)
    }

    @MainActor
    func applyToWindow(_ window: NSWindow) {
        switch self {
        case .system:
            window.appearance = nil
        case .light:
            window.appearance = NSAppearance(named: .aqua)
        case .dark:
            window.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let tabManager = TabManager()
    private var stateToWindow: [UUID: NSWindow] = [:]
    private let tabShortcutLimit = 9
    private var tabRefreshScheduled = false
    private let delegateManager = WindowDelegateManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        buildMenuBar()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidUpdate(_:)),
            name: NSApplication.didUpdateNotification,
            object: nil
        )
        openNewTab()
        if let window = NSApp.keyWindow {
            AppAppearance.current.applyToWindow(window)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc func openNewTab() {
        let state = tabManager.createTab()
        createWindow(for: state)
    }

    @objc func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    @objc func setAppearance(_ sender: NSMenuItem) {
        guard let appearance = AppAppearance(rawValue: sender.tag) else { return }
        appearance.apply()
        for window in NSApp.windows {
            appearance.applyToWindow(window)
        }
        if let menu = sender.menu {
            for item in menu.items where item.tag >= 0 {
                item.state = item.tag == sender.tag ? .on : .off
            }
        }
    }

    @objc func newWindowForTab(_ sender: Any?) {
        openNewTab()
    }

    @objc func selectNextTab() {
        guard let tabGroup = NSApp.keyWindow?.tabGroup,
            let current = NSApp.keyWindow,
            let index = tabGroup.windows.firstIndex(of: current)
        else { return }
        let next = tabGroup.windows[(index + 1) % tabGroup.windows.count]
        next.makeKeyAndOrderFront(nil)
    }

    @objc func selectPreviousTab() {
        guard let tabGroup = NSApp.keyWindow?.tabGroup,
            let current = NSApp.keyWindow,
            let index = tabGroup.windows.firstIndex(of: current)
        else { return }
        let prev = tabGroup.windows[(index - 1 + tabGroup.windows.count) % tabGroup.windows.count]
        prev.makeKeyAndOrderFront(nil)
    }

    @objc func selectTabByNumber(_ sender: NSMenuItem) {
        selectTab(at: sender.tag - 1)
    }

    private func createWindow(for state: ConnectionState) {
        let contentView = TabContentView()
            .environment(state)
            .environment(AppStore.shared)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Redis Console"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: contentView)
        window.collectionBehavior.insert(NSWindow.CollectionBehavior.fullScreenPrimary)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "RedisConsole"

        // Add as tab to existing window, or show as new window
        if let existingWindow = NSApp.keyWindow {
            existingWindow.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
        }

        AppAppearance.current.applyToWindow(window)
        stateToWindow[state.id] = window
        requestTabChromeRefresh()

        // Clean up when window closes
        let delegate = WindowDelegate { [weak self] in
            Task { @MainActor in
                self?.tabManager.closeTab(state)
                self?.stateToWindow.removeValue(forKey: state.id)
                self?.requestTabChromeRefresh()
            }
        }
        window.delegate = delegate
        delegateManager.setDelegate(delegate, for: window)
    }

    private func buildMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About Redis Console",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Redis Console",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // File menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        let newTabItem = NSMenuItem(title: "New Tab", action: #selector(openNewTab), keyEquivalent: "t")
        newTabItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(newTabItem)
        let closeTabItem = NSMenuItem(title: "Close Tab", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeTabItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(closeTabItem)
        fileMenuItem.submenu = fileMenu

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        let nextTabItem = NSMenuItem(title: "Show Next Tab", action: #selector(selectNextTab), keyEquivalent: "→")
        nextTabItem.keyEquivalentModifierMask = [.command]
        windowMenu.addItem(nextTabItem)
        let prevTabItem = NSMenuItem(title: "Show Previous Tab", action: #selector(selectPreviousTab), keyEquivalent: "←")
        prevTabItem.keyEquivalentModifierMask = [.command]
        windowMenu.addItem(prevTabItem)
        windowMenu.addItem(.separator())
        for index in 1...tabShortcutLimit {
            let item = NSMenuItem(
                title: "Select Tab \(index)",
                action: #selector(selectTabByNumber(_:)),
                keyEquivalent: "\(index)"
            )
            item.tag = index
            item.keyEquivalentModifierMask = [.command]
            windowMenu.addItem(item)
        }
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        // Edit menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        // View menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        let fsItem = NSMenuItem(title: "Enter Full Screen", action: #selector(toggleFullScreen), keyEquivalent: "f")
        fsItem.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fsItem)
        viewMenu.addItem(.separator())
        let currentAppearance = AppAppearance.current
        for appearance in AppAppearance.allCases {
            let item = NSMenuItem(
                title: appearance.name,
                action: #selector(setAppearance(_:)),
                keyEquivalent: ""
            )
            item.tag = appearance.rawValue
            item.target = self
            item.state = currentAppearance == appearance ? .on : .off
            viewMenu.addItem(item)
        }
        viewMenuItem.submenu = viewMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func handleApplicationDidUpdate(_ notification: Notification) {
        requestTabChromeRefresh()
    }

    private func requestTabChromeRefresh() {
        guard !tabRefreshScheduled else { return }
        tabRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tabRefreshScheduled = false
            self.refreshTabChrome()
        }
    }

    private func refreshTabChrome() {
        var refreshedGroups = Set<ObjectIdentifier>()

        for window in stateToWindow.values {
            if let tabGroup = window.tabGroup {
                let groupID = ObjectIdentifier(tabGroup)
                guard refreshedGroups.insert(groupID).inserted else { continue }
                syncTabAccessories(in: tabGroup.windows)
            } else {
                syncTabAccessories(in: [window])
            }
        }
    }

    private func selectTab(at index: Int) {
        guard index >= 0 else { return }

        let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow
        if let tabGroup = targetWindow?.tabGroup, index < tabGroup.windows.count {
            tabGroup.windows[index].makeKeyAndOrderFront(nil)
        } else if index == 0 {
            targetWindow?.makeKeyAndOrderFront(nil)
        }
    }

    private func syncTabAccessories(in windows: [NSWindow]) {
        for (index, window) in windows.enumerated() {
            if windows.count > 1, index < tabShortcutLimit {
                window.tab.accessoryView = makeTabAccessoryView(text: "⌘\(index + 1)")
            } else {
                window.tab.accessoryView = nil
            }
        }
    }

    private func makeTabAccessoryView(text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.alignment = .center
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.drawsBackground = false
        label.isBezeled = false
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 34),
            container.heightAnchor.constraint(equalToConstant: 16),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }
}

// MARK: - Window Delegate

class WindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

// MARK: - App Entry Point

@main
struct RedisConsoleApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
