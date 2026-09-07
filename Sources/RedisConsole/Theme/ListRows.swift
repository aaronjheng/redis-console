import AppKit
import SwiftUI

// MARK: - Double Click Handler

/// A SwiftUI wrapper for detecting double-clicks on views, backed by AppKit.
struct DoubleClickHandler: NSViewRepresentable {
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> DoubleClickView {
        let view = DoubleClickView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: DoubleClickView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }
}

class DoubleClickView: NSView {
    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            onDoubleClick?()
        }
    }
}

// MARK: - Copyable Cells

struct CopyableCellModifier: ViewModifier {
    let cellValue: String
    let rowValue: String

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Copy Cell") {
                copyToPasteboard(cellValue)
            }
            Button("Copy Row") {
                copyToPasteboard(rowValue)
            }
        }
    }
}

extension View {
    func copyableCell(_ cellValue: String, row: String) -> some View {
        modifier(CopyableCellModifier(cellValue: cellValue, rowValue: row))
    }
}

// MARK: - Full-Width List Row

private struct ListRowIsSelectedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the enclosing full-width list row is painted with the emphasized
    /// selection highlight, so row content can flip to legible on-selection colors.
    var listRowIsSelected: Bool {
        get { self[ListRowIsSelectedKey.self] }
        set { self[ListRowIsSelectedKey.self] = newValue }
    }
}

extension View {
    /// Draws the chrome of a full-width list row: the selection highlight and
    /// a 1pt bottom separator, both spanning the enclosing scroll container
    /// edge to edge (connecting to the split-view dividers on both sides).
    ///
    /// Neither can be left to the system: the row separator's leading inset
    /// follows row indentation and `listRowInsets` can't remove it on macOS,
    /// and the selection highlight is inset from the row edges. So we hide the
    /// system separator and paint both ourselves, sized to the container's
    /// width with `containerRelativeFrame`. This assumes the row fills the
    /// container's width, which plain `LazyVStack` rows do (namespace tree
    /// depth is drawn as internal padding).
    ///
    /// The highlight uses `selectedContentBackgroundColor`, the same emphasized
    /// selection color the system paints list rows with: it follows the accent
    /// color and stays vivid in dark mode, unlike `selectedControlColor`, which
    /// is a control-face color that resolves to a desaturated slate blue there.
    /// That fill is strong in both appearances, so the selected state is also
    /// published through the `listRowIsSelected` environment value, letting row
    /// content flip to on-selection foreground colors (white) like native lists.
    ///
    /// The separator is drawn as an overlay, except on the selected row where
    /// it is hidden: the selection highlight already marks the row boundary,
    /// and a line painted over the opaque selection color would read much
    /// heavier than the neighboring separators. Hiding it matches native
    /// table behavior, where no separator is drawn at the selection edge.
    func fullWidthListRow(selected: Bool) -> some View {
        self
            .listRowSeparator(.hidden)
            .environment(\.listRowIsSelected, selected)
            .background {
                Color(nsColor: .selectedContentBackgroundColor)
                    .containerRelativeFrame(.horizontal)
                    .opacity(selected ? 1 : 0)
            }
            .overlay(alignment: .bottom) {
                Color(nsColor: .separatorColor)
                    .frame(height: 1)
                    .containerRelativeFrame(.horizontal)
                    .opacity(selected ? 0 : 1)
            }
    }
}

// MARK: - Inline Text Field

struct InlineTextField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textField.delegate = context.coordinator
        textField.focusRingType = .none
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.window?.makeFirstResponder(nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: InlineTextField
        private var isCancelling = false
        private var isSubmitting = false

        init(_ parent: InlineTextField) {
            self.parent = parent
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                isSubmitting = true
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                isCancelling = true
                parent.onCancel()
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            defer {
                isCancelling = false
                isSubmitting = false
            }
            guard !isCancelling, !isSubmitting else { return }
            parent.onSubmit()
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
    }
}
