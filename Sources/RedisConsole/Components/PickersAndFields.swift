import AppKit
import SwiftUI

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
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 13, weight: .medium))
                .imageScale(.medium)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .background(
            isSelected
                ? Color.primary.opacity(0.12)
                : isHovering ? Color.primary.opacity(0.06) : Color.clear,
            in: backgroundShape
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
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
    /// Icon buttons are full field height (22pt) with 8pt trailing padding
    /// and a 6pt text gap; the static glass icon is ~16pt wide.
    private var trailingInset: CGFloat {
        if !text.isEmpty {
            return onSearch != nil ? 62 : 56
        }
        return onSearch != nil ? 36 : 30
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onSearch?() }
                .padding(.trailing, trailingInset)

            HStack(spacing: AppSpacing.xSmall) {
                if !text.isEmpty {
                    FilterFieldIconButton(
                        title: "Clear Filter",
                        systemImage: "xmark.circle.fill",
                        helpText: "Clear filter"
                    ) {
                        text = ""
                        onSearch?()
                    }
                }
                if let onSearch {
                    FilterFieldIconButton(
                        title: "Search",
                        systemImage: "magnifyingglass",
                        helpText: "Search",
                        action: onSearch
                    )
                } else {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.trailing, AppSpacing.small)
        }
    }
}

/// Trailing icon button inside `FilterField`, sized to the full height of the
/// rounded-border field so its hover wash lines up with the field top to
/// bottom instead of floating as a smaller square.
private struct FilterFieldIconButton: View {
    let title: String
    let systemImage: String
    let helpText: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(isHovering ? .primary : .secondary)
            .frame(width: AppSize.filterFieldHeight, height: AppSize.filterFieldHeight)
            .contentShape(Rectangle())
            .background(
                Color.primary.opacity(isHovering ? 0.08 : 0),
                in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
            )
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .help(helpText)
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
    @State private var isHovering = false

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
                    if selection == option {
                        Label(label(option), systemImage: "checkmark")
                    } else {
                        Text(label(option))
                    }
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
            .background(
                Color.primary.opacity(isHovering ? 0.06 : 0),
                in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(title)
    }
}
