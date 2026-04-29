import SwiftUI

struct PersistentSplitView<Left: View, Right: View>: NSViewControllerRepresentable {
    let left: Left
    let right: Right
    let storageKey: String
    let defaultRatio: CGFloat
    let leftMinWidth: CGFloat
    let rightMinWidth: CGFloat

    init(
        storageKey: String,
        defaultRatio: CGFloat = 0.4,
        leftMinWidth: CGFloat = 250,
        rightMinWidth: CGFloat = 250,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) {
        self.storageKey = storageKey
        self.defaultRatio = defaultRatio
        self.leftMinWidth = leftMinWidth
        self.rightMinWidth = rightMinWidth
        self.left = left()
        self.right = right()
    }

    func makeNSViewController(context: Context) -> SplitViewController {
        let controller = SplitViewController()
        controller.storageKey = storageKey
        controller.defaultRatio = defaultRatio

        let leftHost = NSHostingController(rootView: left)
        leftHost.sizingOptions = []
        let leftItem = NSSplitViewItem(viewController: leftHost)
        leftItem.minimumThickness = leftMinWidth
        leftItem.holdingPriority = .init(260)

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
        var storageKey: String = ""
        var defaultRatio: CGFloat = 0.4
        private var restored = false
        private var userDragged = false

        override func viewWillAppear() {
            super.viewWillAppear()
            guard !restored else { return }
            restored = true

            let total = splitView.frame.width
            guard total > 0 else { return }
            let savedRatio = UserDefaults.standard.object(forKey: storageKey) as? CGFloat
            let ratio = savedRatio ?? defaultRatio
            let position = total * ratio
            splitView.setPosition(position, ofDividerAt: 0)
        }

        override func splitViewDidResizeSubviews(_ notification: Notification) {
            super.splitViewDidResizeSubviews(notification)
            guard userDragged else { return }
            let position = splitViewItems[0].viewController.view.frame.width
            let total = splitView.frame.width
            guard total > 0 else { return }
            let ratio = position / total
            UserDefaults.standard.set(ratio, forKey: storageKey)
        }

        override func splitView(
            _ splitView: NSSplitView,
            constrainSplitPosition proposedPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            userDragged = true
            return proposedPosition
        }
    }
}
