import SwiftUI

struct PersistentSplitView<Left: View, Right: View>: NSViewControllerRepresentable {
    let left: Left
    let right: Right
    let leftMinWidth: CGFloat
    let rightMinWidth: CGFloat

    init(
        leftMinWidth: CGFloat = 250,
        rightMinWidth: CGFloat = 250,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) {
        self.leftMinWidth = leftMinWidth
        self.rightMinWidth = rightMinWidth
        self.left = left()
        self.right = right()
    }

    func makeNSViewController(context: Context) -> SplitViewController {
        let controller = SplitViewController()

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
        override func viewWillAppear() {
            super.viewWillAppear()
            let total = splitView.frame.width
            guard total > 0 else { return }
            splitView.setPosition(total * 0.4, ofDividerAt: 0)
        }
    }
}
