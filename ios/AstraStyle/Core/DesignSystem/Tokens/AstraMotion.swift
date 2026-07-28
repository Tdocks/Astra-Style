//
//  AstraMotion.swift
//  AstraStyle
//
//  Motion and haptics tokens (spec §3 "Motion"). All animation call sites should route through
//  `AstraMotion` / `View.astraAnimation(_:value:)` so Reduce Motion is respected everywhere,
//  rather than each feature remembering to check the environment itself.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Standard transition and interaction animations, per spec §3.
public enum AstraMotion {
    /// Standard transition: 220 ms ease-in-out, per spec §3.
    public static let standard: Animation = .easeInOut(duration: 0.22)

    /// Outfit alternatives: horizontal paging with spring settling, per spec §3.
    public static let outfitPaging: Animation = .spring(response: 0.45, dampingFraction: 0.86, blendDuration: 0.1)

    /// Kyra orb/avatar breathing animation — subtle, slow, never distracting, per spec §3.
    /// Intended to be applied to a looping scale/opacity effect via `.repeatForever(autoreverses: true)`.
    public static let breathing: Animation = .easeInOut(duration: 2.4)

    /// Returns `animation` unchanged, or `nil` when Reduce Motion is enabled (spec §3 "Respect
    /// Reduce Motion"; spec §19 "Reduce Motion support"). A `nil` animation makes SwiftUI apply
    /// the change immediately, with no interpolation.
    public static func aware(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// A Reduce Motion-aware replacement for `View.animation(_:value:)`.
private struct AstraAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(AstraMotion.aware(animation, reduceMotion: reduceMotion), value: value)
    }
}

public extension View {
    /// Animates changes to `value` using `animation`, automatically becoming a no-op animation
    /// when the user has Reduce Motion enabled.
    func astraAnimation(_ animation: Animation, value: some Equatable) -> some View {
        modifier(AstraAnimationModifier(animation: animation, value: value))
    }
}

// MARK: - Haptics

/// Haptic feedback map, per spec §3: "selection for outfit swaps; success for saved closet
/// scan; warning for destructive actions."
///
/// Wraps `UIFeedbackGenerator` subclasses, which are UIKit types that must be prepared and
/// triggered on the main actor.
@MainActor
public enum AstraHaptics {
    /// Outfit swaps and other lightweight selection changes.
    public static func selection() {
        #if canImport(UIKit)
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }

    /// Confirms a successful save, e.g. a completed closet scan.
    public static func success() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #endif
    }

    /// Precedes a destructive action (e.g. archiving or deleting a closet item).
    public static func warning() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
        #endif
    }
}
