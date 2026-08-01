import AppKit
import SwiftUI

// MARK: - Collection Detail Controls

func detailCountText(loaded: Int, total: Int?, noun: String) -> String {
    if let total {
        return "\(loaded) / \(total) \(noun)"
    }
    return "\(loaded) \(noun)"
}

private struct CopyableCellModifier: ViewModifier {
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
