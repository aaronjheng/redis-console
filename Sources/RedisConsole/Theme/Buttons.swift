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
