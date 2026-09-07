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
