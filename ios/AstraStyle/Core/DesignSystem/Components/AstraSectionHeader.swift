//
//  AstraSectionHeader.swift
//  AstraStyle
//
//  Editorial section header pairing a serif title with an optional micro-styled eyebrow label
//  and a trailing action (used throughout Home, Closet, and Discover per spec §6).
//

import SwiftUI

/// A section header: optional eyebrow label (`micro` style, e.g. "TODAY'S LOOK") above a serif
/// title (`title2`), with an optional trailing text action (e.g. "See all").
public struct AstraSectionHeader: View {
    private let title: String
    private let eyebrow: String?
    private let actionTitle: String?
    private let action: (() -> Void)?

    /// - Parameters:
    ///   - title: The section's serif title, e.g. "Alternative Looks".
    ///   - eyebrow: Optional micro-styled label shown above the title, e.g. "KYRA'S PICKS".
    ///   - actionTitle: Optional trailing action label, e.g. "See all".
    ///   - action: Invoked when the trailing action is tapped. Required if `actionTitle` is set.
    public init(
        title: String,
        eyebrow: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.eyebrow = eyebrow
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: AstraSpacing.sm) {
            VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                if let eyebrow {
                    Text(eyebrow)
                        .astraText(.micro)
                        .foregroundStyle(AstraColor.accentChampagneAccessible)
                }
                Text(title)
                    .astraText(.title2)
                    .foregroundStyle(AstraColor.textPrimary)
            }

            Spacer(minLength: AstraSpacing.sm)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.astraTertiary)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
