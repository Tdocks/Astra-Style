//
//  GeneratedImageBadge.swift
//  AstraStyle
//
//  The mandatory "visual estimate" disclosure required on every Style Studio generated image
//  (spec §6.17 "Clearly label generated imagery as an approximation"; spec §11 guardrail "Label
//  visual generations as estimates"; spec §13 disclaimer language).
//

import SwiftUI

/// The disclosure badge itself: a small "Visual Estimate" pill.
///
/// Do not place this directly on a generated image from feature code — use
/// ``GeneratedImageContainer`` instead, which pairs the badge with the required accessible alt
/// description (spec §19: "Generated images require editable alt descriptions") and makes it
/// structurally hard to show a generated image without either.
public struct GeneratedImageBadge: View {
    public init() {}

    public var body: some View {
        Label {
            Text("Visual Estimate")
                .astraText(.micro)
        } icon: {
            Image(systemName: "sparkles")
                .imageScale(.small)
        }
        .foregroundStyle(AstraColor.textPrimary)
        .padding(.horizontal, AstraSpacing.sm)
        .padding(.vertical, AstraSpacing.xxs)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(AstraColor.divider, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// The **only sanctioned way** to present Style Studio generated imagery.
///
/// Wrapping generated content in `GeneratedImageContainer` guarantees two things every
/// generated image is required to have and that are easy to forget under deadline pressure:
///
/// 1. The `GeneratedImageBadge` "Visual Estimate" disclosure, always visible, never optional.
/// 2. A required, human-editable accessibility description (spec §19), rather than a missing or
///    auto-generated one.
///
/// Feature code building Style Studio, Daily Brief hero cards, outfit visualization, or the
/// lookbook should reach for this type rather than rendering a generated `Image`/`AsyncImage`
/// directly and applying `astraGeneratedImageBadge()` by hand — that path exists only for
/// retrofitting an existing view hierarchy, and is easy to accidentally skip in a future edit.
public struct GeneratedImageContainer<Content: View>: View {
    private let accessibilityDescription: String
    private let content: Content

    /// - Parameters:
    ///   - accessibilityDescription: A required, editable alt description for the generated
    ///     image (spec §19). Do not pass an empty string — surface the editing UI to the user
    ///     instead of shipping a generated image with no description.
    ///   - content: The generated image content (e.g. an `AsyncImage` or cached `Image`).
    public init(accessibilityDescription: String, @ViewBuilder content: () -> Content) {
        self.accessibilityDescription = accessibilityDescription
        self.content = content()
    }

    public var body: some View {
        content
            .accessibilityLabel(Text(accessibilityDescription))
            .overlay(alignment: .bottomLeading) {
                GeneratedImageBadge()
                    .padding(AstraSpacing.sm)
            }
    }
}

public extension View {
    /// Overlays the mandatory "Visual Estimate" badge directly on this view.
    ///
    /// Prefer ``GeneratedImageContainer`` for new Style Studio surfaces, since it also enforces
    /// the required accessibility description. Use this modifier only when retrofitting an
    /// existing view hierarchy that cannot easily adopt the container.
    func astraGeneratedImageBadge() -> some View {
        overlay(alignment: .bottomLeading) {
            GeneratedImageBadge()
                .padding(AstraSpacing.sm)
        }
    }
}
