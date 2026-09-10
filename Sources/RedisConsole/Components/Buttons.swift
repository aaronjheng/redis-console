import AppKit
import SwiftUI

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
        return isHovering ? 0.12 : 0
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
            .background {
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .fill(.background.secondary)
            }
            .background {
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .fill(Color.primary.opacity(isHovering && !configuration.isPressed ? 0.06 : 0))
            }
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
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.body)
            .foregroundStyle(.primary)
            .padding(AppSpacing.small - AppSpacing.xxSmall)
            .background(
                configuration.isPressed
                    ? Color.primary.opacity(0.12)
                    : isHovering ? Color.primary.opacity(0.08) : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Icon buttons

/// Icon-only button with explicit hover + press feedback.
/// Use in place of `.buttonStyle(.borderless)` for toolbar icons, row actions,
/// and dismiss buttons so hit areas are discoverable on hover.
/// Sizing for `IconButtonStyle`: total height is frame + padding so each
/// variant pairs with its neighbors — regular (28pt) matches
/// `RefreshControl`, row is glyph-sized so `Table` rows keep text height
/// instead of being stretched by their action buttons.
enum IconButtonSize: Sendable {
    case regular
    case row

    /// Fixed inner frame; nil sizes to the glyph.
    var minSide: CGFloat? {
        switch self {
        case .regular: return 20
        case .row: return nil
        }
    }

    var padding: CGFloat {
        switch self {
        case .regular: return AppSpacing.xSmall
        case .row: return AppSpacing.xxSmall
        }
    }
}

struct IconButtonStyle: ButtonStyle {
    var isDestructive = false
    var size: IconButtonSize = .regular
    var weight: Font.Weight = .medium
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: weight))
            .imageScale(.medium)
            .frame(minWidth: size.minSide ?? 0, minHeight: size.minSide ?? 0)
            .padding(size.padding)
            .background(
                hoverBackground(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
            )
            .brightness(configuration.isPressed ? -0.06 : 0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private func hoverBackground(isPressed: Bool) -> Color {
        if isPressed {
            return isDestructive ? Color.red.opacity(0.16) : Color.primary.opacity(0.12)
        }
        if isHovering {
            return isDestructive ? Color.red.opacity(0.1) : AppColor.iconHoverBackground
        }
        return Color.clear
    }
}

// MARK: - Hover background for custom rows

private struct HoverBackgroundModifier: ViewModifier {
    var cornerRadius: CGFloat = AppRadius.small
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                isHovering ? AppColor.hoverBackground : Color.clear,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

extension View {
    /// Subtle hover wash for custom tappable rows/cards that don't use a
    /// `ButtonStyle` (e.g. `onTapGesture` rows, section headers).
    func hoverBackground(
        cornerRadius: CGFloat = AppRadius.small
    ) -> some View {
        modifier(HoverBackgroundModifier(cornerRadius: cornerRadius))
    }
}
