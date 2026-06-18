import SwiftUI

struct PersistentSplitView<Left: View, Right: View>: NSViewControllerRepresentable {
    let dividerPositionKey: String
    let left: Left
    let right: Right
    let leftMinWidth: CGFloat
    let rightMinWidth: CGFloat

    init(
        dividerPositionKey: String = "com.redisconsole.browserSplitDividerPosition.v2",
        leftMinWidth: CGFloat = 250,
        rightMinWidth: CGFloat = 250,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) {
        self.dividerPositionKey = dividerPositionKey
        self.leftMinWidth = leftMinWidth
        self.rightMinWidth = rightMinWidth
        self.left = left()
        self.right = right()
    }

    func makeNSViewController(context: Context) -> SplitViewController {
        let controller = SplitViewController(dividerPositionKey: dividerPositionKey)

        let leftHost = NSHostingController(rootView: left)
        leftHost.sizingOptions = []
        let leftItem = NSSplitViewItem(viewController: leftHost)
        leftItem.minimumThickness = leftMinWidth

        let rightHost = NSHostingController(rootView: right)
        rightHost.sizingOptions = []
        let rightItem = NSSplitViewItem(viewController: rightHost)
        rightItem.minimumThickness = rightMinWidth

        controller.addSplitViewItem(leftItem)
        controller.addSplitViewItem(rightItem)
        controller.splitView.dividerStyle = .thin

        return controller
    }

    func updateNSViewController(_ nsViewController: SplitViewController, context: Context) {
        if let leftHost = nsViewController.splitViewItems[0].viewController as? NSHostingController<Left> {
            leftHost.rootView = left
        }
        if let rightHost = nsViewController.splitViewItems[1].viewController as? NSHostingController<Right> {
            rightHost.rootView = right
        }
    }

    class SplitViewController: NSSplitViewController {
        private let dividerPositionKey: String
        private var didRestoreDividerPosition = false

        init(dividerPositionKey: String) {
            self.dividerPositionKey = dividerPositionKey
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLayout() {
            super.viewDidLayout()
            restoreDividerPositionIfNeeded()
        }

        override func splitViewDidResizeSubviews(_ notification: Notification) {
            super.splitViewDidResizeSubviews(notification)
            saveDividerPosition()
        }

        private func restoreDividerPositionIfNeeded() {
            guard !didRestoreDividerPosition else { return }
            let total = splitView.frame.width
            guard total > 0 else { return }

            let storedFraction = UserDefaults.standard.object(forKey: dividerPositionKey) as? Double
            let fraction = CGFloat(storedFraction ?? 0.4)
            let minPosition = splitViewItems[0].minimumThickness
            let maxPosition = total - splitViewItems[1].minimumThickness
            let position = min(max(total * fraction, minPosition), maxPosition)

            didRestoreDividerPosition = true
            splitView.setPosition(position, ofDividerAt: 0)
        }

        private func saveDividerPosition() {
            guard didRestoreDividerPosition else { return }
            let total = splitView.frame.width
            guard total > 0, let leftWidth = splitViewItems.first?.viewController.view.frame.width else { return }
            let fraction = min(max(leftWidth / total, 0.1), 0.9)
            UserDefaults.standard.set(Double(fraction), forKey: dividerPositionKey)
        }
    }
}
