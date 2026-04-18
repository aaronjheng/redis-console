import SwiftUI

// MARK: - Theme Constants

enum AppTheme {
    static let spacing: CGFloat = 8
    static let spacingSmall: CGFloat = 4
    static let spacingLarge: CGFloat = 16
    static let spacingXLarge: CGFloat = 20

    static let cornerRadiusSmall: CGFloat = 4
    static let cornerRadiusMedium: CGFloat = 6

    static let emptyStateIconSize: CGFloat = 48
    static let welcomeIconSize: CGFloat = 64

    static let tabBarHeight: CGFloat = 32
    static let sheetWidth: CGFloat = 400

    // MARK: - Background Colors
    static var sidebarBackground: Color {
        Color(white: 0.95)
    }
}

// MARK: - Reusable Empty State View

struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: AppTheme.spacing) {
            Image(systemName: icon)
                .font(.system(size: AppTheme.emptyStateIconSize))
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if let actionTitle, let action {
                Button(actionTitle) { action() }
            }
        }
    }
}

// MARK: - Reusable Sheet Layout

struct SheetLayout<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var cancelAction: () -> Void
    var primaryAction: (() -> Void)?
    var primaryActionTitle: String
    var isPrimaryDisabled: Bool

    init(
        title: String,
        cancelAction: @escaping () -> Void,
        primaryActionTitle: String = "Add",
        isPrimaryDisabled: Bool = false,
        primaryAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.cancelAction = cancelAction
        self.primaryActionTitle = primaryActionTitle
        self.isPrimaryDisabled = isPrimaryDisabled
        self.primaryAction = primaryAction
        self.content = content()
    }

    var body: some View {
        VStack(spacing: AppTheme.spacingLarge) {
            Text(title)
                .font(.headline)

            content
                .formStyle(.grouped)

            HStack {
                Button("Cancel") { cancelAction() }
                Spacer()
                if let primaryAction {
                    Button(primaryActionTitle) { primaryAction() }
                        .disabled(isPrimaryDisabled)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding()
        .frame(width: AppTheme.sheetWidth)
    }
}

// MARK: - Reusable Status Footer

struct StatusFooterView: View {
    let countText: String
    var sizeText: String?

    init(countText: String, sizeText: String? = nil) {
        self.countText = countText
        self.sizeText = sizeText
    }

    var body: some View {
        HStack(spacing: AppTheme.spacingSmall) {
            Text(countText)
            if let sizeText {
                Text("\u{00B7}")
                Text(sizeText)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Reusable Delete Button

struct DeleteIconButton: View {
    let action: () -> Void
    var helpText: String?

    init(action: @escaping () -> Void, helpText: String? = nil) {
        self.action = action
        self.helpText = helpText
    }

    var body: some View {
        Button(role: .destructive) {
            action()
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .help(helpText ?? "Delete")
    }
}
