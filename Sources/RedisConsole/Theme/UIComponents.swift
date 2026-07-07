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
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.small - AppSpacing.xxSmall)
            .font(.system(.body, design: .default))
            .foregroundStyle(.white)
            .background(.tint)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// A secondary button style that renders reliably in off-screen captures.
/// Use this in place of `.buttonStyle(.bordered)`.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.small - AppSpacing.xxSmall)
            .font(.system(.body, design: .default))
            .foregroundStyle(.primary)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
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
struct BinaryTogglePicker<Option: Hashable & Sendable>: View {
    let options: (first: Option, second: Option)
    let firstLabel: AnyView
    let secondLabel: AnyView
    @Binding var selection: Option

    init(
        selection: Binding<Option>,
        first: Option,
        second: Option,
        @ViewBuilder firstLabel: () -> some View,
        @ViewBuilder secondLabel: () -> some View
    ) {
        self._selection = selection
        self.options = (first, second)
        self.firstLabel = AnyView(firstLabel())
        self.secondLabel = AnyView(secondLabel())
    }

    var body: some View {
        HStack(spacing: 0) {
            ToggleButton(isSelected: selection == options.first) {
                selection = options.first
            } label: {
                firstLabel
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: AppRadius.medium,
                    bottomLeadingRadius: AppRadius.medium,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )

            ToggleButton(isSelected: selection == options.second) {
                selection = options.second
            } label: {
                secondLabel
            }
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
        .frame(height: AppSize.refreshControlHeight)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}

private struct ToggleButton<Label: View>: View {
    let isSelected: Bool
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
        .background(isSelected ? Color.primary.opacity(0.12) : Color.clear)
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
