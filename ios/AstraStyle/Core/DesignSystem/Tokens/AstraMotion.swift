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

    /// Whether a shared hero should morph between layouts. Reduce Motion uses the
    /// opacity transition in `astraHeroTransition` instead of moving geometry.
    public static func usesMatchedGeometry(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    /// A repeating breathing animation is omitted entirely when Reduce Motion is on.
    public static func breathingAnimation(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return breathing.repeatForever(autoreverses: true)
    }

    /// Spring-settling outfit paging animation, omitted when Reduce Motion is enabled.
    public static func outfitPagingAnimation(reduceMotion: Bool) -> Animation? {
        aware(outfitPaging, reduceMotion: reduceMotion)
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

    /// Applies a shared-element hero transition. Reduce Motion replaces the geometry
    /// interpolation with a simple cross-fade.
    func astraHeroTransition<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID,
        isSource: Bool = true
    ) -> some View {
        modifier(AstraHeroTransitionModifier(id: id, namespace: namespace, isSource: isSource))
    }

    /// Applies Astra's slow breathing loop to a state-driven visual effect, with a static
    /// presentation for users who enable Reduce Motion.
    func astraBreathingAnimation(value: some Equatable) -> some View {
        modifier(AstraBreathingAnimationModifier(value: value))
    }

    /// Uses Astra's horizontal outfit paging spring, becoming an immediate state change
    /// when Reduce Motion is enabled.
    func astraOutfitPagingAnimation(value: some Equatable) -> some View {
        modifier(AstraOutfitPagingAnimationModifier(value: value))
    }
}

private struct AstraHeroTransitionModifier<ID: Hashable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let id: ID
    let namespace: Namespace.ID
    let isSource: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if AstraMotion.usesMatchedGeometry(reduceMotion: reduceMotion) {
            content.matchedGeometryEffect(id: id, in: namespace, isSource: isSource)
        } else {
            content.transition(.opacity)
        }
    }
}

private struct AstraBreathingAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    func body(content: Content) -> some View {
        content.animation(AstraMotion.breathingAnimation(reduceMotion: reduceMotion), value: value)
    }
}

private struct AstraOutfitPagingAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    func body(content: Content) -> some View {
        content.animation(AstraMotion.outfitPagingAnimation(reduceMotion: reduceMotion), value: value)
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
