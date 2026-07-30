import AppKit
import SwiftUI

/// A read-only, selectable text view backed by `NSTextView`.
///
/// SwiftUI's `Text` with `.textSelection(.enabled)` lazily swaps in an
/// `NSTextView` on first click, which causes a visible relayout (especially
/// around blank lines) -- a "jitter". This wrapper uses a bare `NSTextView`
/// (no enclosing scroll view) from the start, so there is no swap. To make a
/// bare `NSTextView` size correctly inside SwiftUI's layout system, it reports
/// an `intrinsicContentSize` computed from its layout manager.
struct SelectableText: NSViewRepresentable {
    let text: String
    var font: NSFont = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    func makeNSView(context: Context) -> AutoSizingTextView {
        let textView = AutoSizingTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.font = font
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.size = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.string = text
        return textView
    }

    func updateNSView(_ nsView: AutoSizingTextView, context: Context) {
        if nsView.string != text {
            nsView.string = text
        }
        if nsView.font != font {
            nsView.font = font
        }
    }
}

/// An `NSTextView` that keeps its `intrinsicContentSize` in sync with its laid
/// out text height, so SwiftUI can measure it without a wrapping scroll view.
final class AutoSizingTextView: NSTextView {
    override var string: String {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    override var font: NSFont? {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: usedRect.height)
    }
}
