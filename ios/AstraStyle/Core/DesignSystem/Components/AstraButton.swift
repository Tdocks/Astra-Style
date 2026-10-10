//
//  AstraButton.swift
//  AstraStyle
//
//  Primary, secondary, and tertiary button styles (spec §3 layout: 14 pt corner radius,
//  44 pt minimum tap target).
//

import SwiftUI

/// Primary button: solid champagne fill with dark on-accent text. Use for the single strongest
/// call to action on a screen (e.g. "Wear This").
public struct AstraPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .astraText(.headline)
            .foregroundStyle(AstraColor.textOnAccent)
            .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: AstraRadius.button, style: .continuous)
                    .fill(configuration.isPressed ? AstraColor.accentChampagnePressed : AstraColor.accentChampagne)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .astraAnimation(AstraMotion.standard, value: configuration.isPressed)
    }
}

/// Secondary button: bordered, transparent fill, champagne-accessible text/border. Use for a
/// clearly available but non-primary action alongside a primary button (e.g. "Alternatives").
public struct AstraSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .astraText(.headline)
            .foregroundStyle(
                AstraColor.accentChampagneAccessible
            )
            .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: AstraRadius.button, style: .continuous)
                    .strokeBorder(
                        AstraColor.accentChampagneAccessible,
                        lineWidth: 1
                    )
            )
            .opacity(isEnabled ? 1 : 0.45)
            .astraAnimation(AstraMotion.standard, value: configuration.isPressed)
    }
}

/// Tertiary button: text-only, no fill or border. Use for low-emphasis actions (e.g. "Skip",
/// "Edit") that still need a full 44 pt tap target.
public struct AstraTertiaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .astraText(.headline)
            .foregroundStyle(
                AstraColor.accentChampagneAccessible
            )
            .frame(minHeight: AstraSize.minTapTarget)
            .padding(.horizontal, AstraSpacing.sm)
            .opacity(isEnabled ? 1 : 0.45)
            .astraAnimation(AstraMotion.standard, value: configuration.isPressed)
    }
}

/// Destructive button: keeps the destructive token on the outline while retaining
/// high-contrast primary text in both appearances. The action label remains textual,
/// so red is not the only cue that the action removes or discards something.
public struct AstraDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .astraText(.headline)
            .foregroundStyle(AstraColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: AstraRadius.button, style: .continuous)
                    .fill(configuration.isPressed ? AstraColor.backgroundSecondary : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AstraRadius.button, style: .continuous)
                    .strokeBorder(AstraColor.destructive, lineWidth: 1.5)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .astraAnimation(AstraMotion.standard, value: configuration.isPressed)
    }
}

public enum AstraButtonVariant: Equatable {
    case primary
    case secondary
    case destructive
}

// MARK: - Convenience view

/// A ready-made primary button: `Button(title, action: action).buttonStyle(.astraPrimary)`.
///
/// Most call sites should prefer `Button("...") { }.buttonStyle(.astraPrimary)` directly (or
/// `.astraSecondary` / `.astraTertiary`) so the label can be a full `ViewBuilder` (icons,
/// `Label`, etc). `AstraButton` exists as a lightweight convenience for the common case of a
/// plain text primary action.
public struct AstraButton: View {
    private let title: String
    private let isLoading: Bool
    private let variant: AstraButtonVariant
    private let action: () -> Void

    /// - Parameters:
    ///   - title: The button's label.
    ///   - isLoading: When `true`, replaces the label with a spinner and disables the button —
    ///     for async primary actions (e.g. "Wear This") that must show in-flight state per spec
    ///     §22's acceptance bar ("no unhandled network failure" implies a visible loading state,
    ///     not a silently-dead tap). Defaults to `false`.
    ///   - action: Invoked on tap.
    ///   - variant: Visual intent for the action. Destructive uses a red outline and
    ///     accessible primary text, keeping the action legible in both appearances.
    public init(
        title: String,
        isLoading: Bool = false,
        variant: AstraButtonVariant = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isLoading = isLoading
        self.variant = variant
        self.action = action
    }

    @ViewBuilder
    public var body: some View {
        let button = Button(action: action) {
            if isLoading {
                ProgressView()
                    .tint(variant == .destructive ? AstraColor.destructive : AstraColor.textOnAccent)
                    .accessibilityLabel(Text(title))
            } else {
                Text(title)
            }
        }
        switch variant {
        case .primary:
            button.buttonStyle(.astraPrimary).disabled(isLoading)
        case .secondary:
            button.buttonStyle(.astraSecondary).disabled(isLoading)
        case .destructive:
            button.buttonStyle(.astraDestructive).disabled(isLoading)
        }
    }
}

// MARK: - Dot-syntax convenience

public extension ButtonStyle where Self == AstraPrimaryButtonStyle {
    /// `Button("Wear This") { }.buttonStyle(.astraPrimary)`
    static var astraPrimary: AstraPrimaryButtonStyle { AstraPrimaryButtonStyle() }
}

public extension ButtonStyle where Self == AstraSecondaryButtonStyle {
    static var astraSecondary: AstraSecondaryButtonStyle { AstraSecondaryButtonStyle() }
}

public extension ButtonStyle where Self == AstraTertiaryButtonStyle {
    static var astraTertiary: AstraTertiaryButtonStyle { AstraTertiaryButtonStyle() }
}

public extension ButtonStyle where Self == AstraDestructiveButtonStyle {
    static var astraDestructive: AstraDestructiveButtonStyle { AstraDestructiveButtonStyle() }
}

#Preview("AstraButton · dark and light") {
    HStack(alignment: .top, spacing: AstraSpacing.md) {
        buttonPreviewColumn(colorScheme: .dark)
        buttonPreviewColumn(colorScheme: .light)
    }
    .padding(AstraSpacing.lg)
    .background(AstraColor.backgroundPrimary)
}

@MainActor
private func buttonPreviewColumn(colorScheme: ColorScheme) -> some View {
    VStack(spacing: AstraSpacing.sm) {
        Text(colorScheme == .dark ? "Dark" : "Light")
            .astraText(.headline)
        AstraButton(title: "Continue", variant: .primary) {}
        AstraButton(title: "Learn more", variant: .secondary) {}
        AstraButton(title: "Delete item", variant: .destructive) {}
    }
    .frame(maxWidth: .infinity)
    .padding(AstraSpacing.sm)
    .background(AstraColor.backgroundPrimary)
    .environment(\.colorScheme, colorScheme)
}
