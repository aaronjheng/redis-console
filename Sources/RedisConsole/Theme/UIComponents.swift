import AppKit
import SwiftUI

struct WorkspaceFooterBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            content
        }
        .font(.caption)
        .controlSize(.regular)
        .imageScale(.medium)
        .padding(.horizontal, AppSpacing.small)
        .frame(minHeight: AppSize.footerHeight)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

/// Standard layout for panel toolbars/headers (Browser, Shell, Profiler, Slow Log, Analysis, Server Info).
/// Enforces a consistent minimum height while still letting a header grow to fit taller content.
struct PanelToolbarModifier: ViewModifier {
    var horizontalPadding: CGFloat = AppSpacing.large

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: AppSize.toolbarHeight)
    }
}

extension View {
    /// Applies the shared panel toolbar layout: standard horizontal padding plus a unified minimum height.
    func panelToolbar(horizontalPadding: CGFloat = AppSpacing.large) -> some View {
        modifier(PanelToolbarModifier(horizontalPadding: horizontalPadding))
    }
}

struct StatusFooterView: View {
    let countText: String
    var sizeText: String?

    init(countText: String, sizeText: String? = nil) {
        self.countText = countText
        self.sizeText = sizeText
    }

    var body: some View {
        HStack(spacing: AppSpacing.xSmall) {
            Text(countText)
            if let sizeText {
                Text("\u{00B7}")
                Text(sizeText)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(nil)
    }
}

struct Badge: View {
    let text: String
    var systemImage: String?
    var foregroundColor: Color = .secondary
    var backgroundColor: Color = AppColor.subtleBackground
    var isLoading: Bool = false

    var body: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .padding(.horizontal, AppSpacing.small - AppSpacing.xxSmall)
                .padding(.vertical, AppSpacing.xxSmall)
                .frame(minWidth: 42)
        } else {
            HStack(spacing: AppSpacing.xxSmall) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(text)
            }
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, AppSpacing.small - AppSpacing.xxSmall)
            .padding(.vertical, AppSpacing.xxSmall)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct ErrorBanner: View {
    enum Severity {
        case error
        case warning

        var icon: String { "exclamationmark.triangle.fill" }
        var color: Color {
            switch self {
            case .error: AppColor.error
            case .warning: AppColor.warning
            }
        }
        var background: Color { AppColor.subtleBackground }
    }

    let message: String
    var severity: Severity = .error
    var dismissAction: (() -> Void)?

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: severity.icon)
                .foregroundStyle(severity.color)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
            if let dismissAction {
                Button("Dismiss", systemImage: "xmark") {
                    dismissAction()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Dismiss")
            }
        }
        .padding(.horizontal, AppSpacing.small)
        .padding(.vertical, AppSpacing.small - AppSpacing.xxSmall)
        .background(severity.background)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
    }
}

struct LoadingState: View {
    let message: String

    var body: some View {
        VStack(spacing: AppSpacing.small) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity)
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
    }
}

struct DeleteIconButton: View {
    let action: () -> Void
    var helpText: String?

    init(action: @escaping () -> Void, helpText: String? = nil) {
        self.action = action
        self.helpText = helpText
    }

    var body: some View {
        Button("Delete", systemImage: "trash", role: .destructive) {
            action()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .help(helpText ?? "Delete")
    }
}

struct RefreshControl: View {
    @Binding var autoRefreshInterval: TimeInterval
    let isLoading: Bool
    let intervals: [TimeInterval]
    let onRefresh: () -> Void

    private var isAutoRefreshEnabled: Bool {
        autoRefreshInterval > 0
    }

    private static func intervalTitle(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        if totalSeconds.isMultiple(of: 60) {
            return "\(totalSeconds / 60)m"
        }
        return "\(totalSeconds)s"
    }

    @State private var isRefreshHovering = false
    @State private var isMenuHovering = false

    var body: some View {
        HStack(spacing: 0) {
            refreshButton
            separator
            intervalMenu
        }
        .frame(height: AppSize.refreshControlHeight)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .opacity(isLoading ? 0.5 : 1)
    }

    private var refreshButton: some View {
        Button {
            onRefresh()
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
                .font(.caption)
                .frame(width: AppSize.refreshButtonWidth, height: AppSize.refreshControlHeight)
                .contentShape(Rectangle())
                .background(
                    isRefreshHovering && !isLoading
                        ? Color.primary.opacity(0.08)
                        : Color.clear
                )
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: AppRadius.medium,
                        bottomLeadingRadius: AppRadius.medium,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { isRefreshHovering = $0 }
        .help("Refresh")
    }

    private var separator: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 0.5, height: AppSize.refreshSeparatorHeight)
    }

    private var intervalMenu: some View {
        Menu {
            Button {
                autoRefreshInterval = 0
            } label: {
                menuItemLabel(text: "Off", checked: !isAutoRefreshEnabled)
            }
            Divider()
            ForEach(intervals, id: \.self) { interval in
                Button {
                    autoRefreshInterval = interval
                } label: {
                    menuItemLabel(
                        text: Self.intervalTitle(interval),
                        checked: isAutoRefreshEnabled && autoRefreshInterval == interval
                    )
                }
            }
        } label: {
            HStack(spacing: 0) {
                if isAutoRefreshEnabled {
                    Text(Self.intervalTitle(autoRefreshInterval))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                        .padding(.horizontal, AppSpacing.small - AppSpacing.xxSmall)
                } else {
                    Color.clear.frame(width: 18, height: AppSize.refreshControlHeight)
                }
            }
            .frame(height: AppSize.refreshControlHeight)
            .contentShape(Rectangle())
            .background(
                isMenuHovering && !isLoading
                    ? Color.primary.opacity(0.08)
                    : Color.clear
            )
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: AppRadius.medium,
                    topTrailingRadius: AppRadius.medium,
                    style: .continuous
                )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .disabled(isLoading)
        .onHover { isMenuHovering = $0 }
        .help(isAutoRefreshEnabled ? "Auto refresh every \(Self.intervalTitle(autoRefreshInterval))" : "Auto refresh off")
    }

    private func menuItemLabel(text: String, checked: Bool) -> some View {
        Text(checked ? "\(text)  \u{2713}" : text)
    }
}

// MARK: - Stable screenshot button styles

/// A primary button style that renders reliably in off-screen captures.
/// Use this in place of `.buttonStyle(.borderedProminent)`.
/// Hover and press feedback are driven by transient state that is idle during
/// off-screen renders, so captured output stays in the stable rest appearance.
struct PrimaryButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.small - AppSpacing.xxSmall)
            .font(.system(.body, design: .default))
            .foregroundStyle(.white)
            .background(.tint)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .brightness(pressedBrightness(configuration))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private func pressedBrightness(_ configuration: Configuration) -> Double {
        if configuration.isPressed { return -0.08 }
        return isHovering ? 0.08 : 0
    }
}

/// A secondary button style that renders reliably in off-screen captures.
/// Use this in place of `.buttonStyle(.bordered)`.
/// Hover and press feedback are driven by transient state that is idle during
/// off-screen renders, so captured output stays in the stable rest appearance.
struct SecondaryButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.small - AppSpacing.xxSmall)
            .font(.system(.body, design: .default))
            .foregroundStyle(.primary)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovering ? 0.14 : 0), lineWidth: 1)
            )
            .brightness(configuration.isPressed ? -0.06 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

/// A toolbar icon-only button style that renders reliably in off-screen captures.
struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.body)
            .foregroundStyle(.primary)
            .padding(AppSpacing.small - AppSpacing.xxSmall)
            .background(configuration.isPressed ? Color.primary.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            .contentShape(Rectangle())
    }
}

// MARK: - Stable screenshot pickers

/// A two-option segmented picker drawn entirely in SwiftUI so it captures reliably.
struct BinaryTogglePicker<Option: Hashable & Sendable, FirstLabel: View, SecondLabel: View>: View {
    let options: (first: Option, second: Option)
    let firstLabel: FirstLabel
    let secondLabel: SecondLabel
    let firstHelp: String?
    let secondHelp: String?
    @Binding var selection: Option

    init(
        selection: Binding<Option>,
        first: Option,
        second: Option,
        firstHelp: String? = nil,
        secondHelp: String? = nil,
        @ViewBuilder firstLabel: () -> FirstLabel,
        @ViewBuilder secondLabel: () -> SecondLabel
    ) {
        self._selection = selection
        self.options = (first, second)
        self.firstHelp = firstHelp
        self.secondHelp = secondHelp
        self.firstLabel = firstLabel()
        self.secondLabel = secondLabel()
    }

    var body: some View {
        HStack(spacing: 0) {
            ToggleButton(
                isSelected: selection == options.first,
                helpText: firstHelp,
                backgroundShape: UnevenRoundedRectangle(
                    topLeadingRadius: AppRadius.medium,
                    bottomLeadingRadius: AppRadius.medium,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            ) {
                selection = options.first
            } label: {
                firstLabel
            }

            ToggleButton(
                isSelected: selection == options.second,
                helpText: secondHelp,
                backgroundShape: UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: AppRadius.medium,
                    topTrailingRadius: AppRadius.medium,
                    style: .continuous
                )
            ) {
                selection = options.second
            } label: {
                secondLabel
            }
        }
        .frame(height: AppSize.refreshControlHeight)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}

private struct ToggleButton<Label: View>: View {
    let isSelected: Bool
    let helpText: String?
    let backgroundShape: UnevenRoundedRectangle
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .background(isSelected ? Color.primary.opacity(0.12) : Color.clear, in: backgroundShape)
        .help(helpText ?? "")
        .accessibilityLabel(helpText ?? "")
    }
}

/// A unified search/filter text field used across all panels.
///
/// When `onSearch` is provided the magnifying-glass icon becomes a tappable
/// search button and Return triggers the callback — suitable for server-side
/// filtering. When `onSearch` is `nil` the field acts as a local filter;
/// the parent simply observes `text` changes.
struct FilterField: View {
    @Binding var text: String
    let placeholder: String
    var onSearch: (() -> Void)?

    init(_ placeholder: String, text: Binding<String>, onSearch: (() -> Void)? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.onSearch = onSearch
    }

    /// Right-side inset so typed text never slides underneath the overlay icons.
    /// One icon visible when empty (magnifying glass ≈ 16 pt + 8 pt trailing + 6 pt gap = 30),
    /// two icons when text is present (clear + glass ≈ 16 + 4 + 16 + 8 + 6 gap = 50).
    private var trailingInset: CGFloat {
        text.isEmpty ? 30 : 50
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onSearch?() }
                .padding(.trailing, trailingInset)

            HStack(spacing: AppSpacing.xSmall) {
                if !text.isEmpty {
                    Button("Clear Filter", systemImage: "xmark.circle.fill") {
                        text = ""
                        onSearch?()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .help("Clear filter")
                }
                if let onSearch {
                    Button("Search", systemImage: "magnifyingglass") {
                        onSearch()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .contentShape(Rectangle())
                    .help("Search")
                } else {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.trailing, AppSpacing.small)
        }
    }
}

/// A small dropdown-style picker drawn entirely in SwiftUI.
/// Use for a small number of text options where a native pop-up button would
/// otherwise render as a white block off-screen.
struct OptionsPicker<Option: Hashable & Sendable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    init(
        _ title: String,
        selection: Binding<Option>,
        options: [Option],
        label: @escaping (Option) -> String
    ) {
        self.title = title
        self._selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .foregroundStyle(selection == option ? .primary : .secondary)
                }
            }
        } label: {
            HStack(spacing: AppSpacing.xSmall) {
                Text(label(selection))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, AppSpacing.small - AppSpacing.xxSmall)
            .foregroundStyle(.primary)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(title)
    }
}

// MARK: - Production Confirmation

/// A typed-confirmation sheet for destructive actions on production databases.
/// Shared by Browser, Key Detail views, and Function Library views.
struct ProductionConfirmView: View {
    let title: String
    let message: String
    let confirmText: String
    @Binding var input: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: AppSpacing.large) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.largeTitle)
                .foregroundStyle(AppColor.error)

            Text(title)
                .font(.title2)
                .bold()

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 0) {
                Image(systemName: "shield")
                    .foregroundStyle(AppColor.error)
                Text("This is a PRODUCTION database.")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.error)
            }

            HStack(spacing: AppSpacing.xSmall) {
                Text("Type \"\(confirmText)\" to confirm:")
                    .font(.subheadline)
                Spacer()
            }

            TextField("", text: $input)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .onSubmit(confirmIfValid)

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Delete", role: .destructive, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(input != confirmText)
            }
        }
        .padding(AppSpacing.large)
        .frame(width: AppSize.productionConfirmWidth)
        .onAppear { isInputFocused = true }
    }

    private func confirmIfValid() {
        if input == confirmText {
            onConfirm()
        }
    }
}

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

// MARK: - Collection Detail Controls

func detailCountText(loaded: Int, total: Int?, noun: String) -> String {
    if let total {
        return "\(loaded) / \(total) \(noun)"
    }
    return "\(loaded) \(noun)"
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
    /// The separator is drawn as an overlay so it stays visible on top of the
    /// selection highlight, and it switches to a primary-tinted line there:
    /// `separatorColor` is a ~10% alpha tint meant for plain backgrounds and
    /// all but disappears over the opaque selection color.
    func fullWidthListRow(selected: Bool) -> some View {
        self
            .listRowSeparator(.hidden)
            .background {
                Color(nsColor: .selectedControlColor)
                    .containerRelativeFrame(.horizontal)
                    .opacity(selected ? 1 : 0)
            }
            .overlay(alignment: .bottom) {
                let lineColor = selected ? Color.primary.opacity(0.2) : Color(nsColor: .separatorColor)
                lineColor
                    .frame(height: 1)
                    .containerRelativeFrame(.horizontal)
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
