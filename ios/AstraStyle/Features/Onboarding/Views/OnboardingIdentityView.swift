//
//  OnboardingIdentityView.swift
//  AstraStyle
//
//  Spec §6.5 — Style identity. "Ask users to choose three, then rank one
//  primary."
//
//  This is the only required step in the flow, because a partial answer here is
//  not a smaller answer — two identities with no primary is unusable, whereas a
//  blank measurements screen degrades gracefully.
//
//  The interaction is two-stage and that is where these screens usually go
//  wrong. Two common failures, both avoided here:
//
//    • Hiding the ranking stage until three are picked, so the user does not
//      know it is coming and feels ambushed by a second task.
//    • Silently swapping out an earlier pick when a fourth card is tapped,
//      which looks like the app losing his choice.
//
//  So the primary prompt is visible (disabled) from the start, and tapping a
//  fourth card is refused with an explanation rather than absorbed.
//

import SwiftUI

struct OnboardingIdentityView: View {
    @Binding var selected: [StyleIdentity]
    @Binding var primary: StyleIdentity?

    @State private var refusedExtraPick = false

    private var required: Int { StyleIdentityRules.requiredSelectionCount }
    private var isSelectionComplete: Bool { selected.count == required }

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.lg) {
            selectionSection
            primarySection
        }
    }

    // MARK: - Stage one: choose three

    private var selectionSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            HStack {
                Text("Choose \(required)")
                    .astraText(.micro)
                    .foregroundStyle(AstraColor.textMuted)
                Spacer()
                Text("\(selected.count)/\(required)")
                    .astraText(.caption)
                    .foregroundStyle(
                        isSelectionComplete ? AstraColor.accentChampagneAccessible : AstraColor.textMuted
                    )
                    .monospacedDigit()
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: AstraSpacing.sm)],
                spacing: AstraSpacing.sm
            ) {
                ForEach(StyleIdentity.allCases, id: \.self) { identity in
                    IdentityCard(
                        identity: identity,
                        selectionOrder: selected.firstIndex(of: identity).map { $0 + 1 },
                        isPrimary: primary == identity,
                        toggle: { toggle(identity) }
                    )
                }
            }

            if refusedExtraPick {
                Text("That's \(required) already. Deselect one to swap it out.")
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.warningAmber)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
    }

    // MARK: - Stage two: nominate a primary

    private var primarySection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text("Which is most you?")
                .astraText(.micro)
                .foregroundStyle(AstraColor.textMuted)

            if selected.isEmpty {
                // Visible but empty from the start, so the second stage is never
                // a surprise.
                Text("Pick \(required) above and they'll appear here.")
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                    .padding(.vertical, AstraSpacing.sm)
            } else {
                VStack(spacing: AstraSpacing.xs) {
                    ForEach(selected, id: \.self) { identity in
                        PrimaryChoiceRow(
                            identity: identity,
                            isPrimary: primary == identity,
                            select: {
                                primary = identity
                                AstraHaptics.selection()
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Selection logic

    private func toggle(_ identity: StyleIdentity) {
        if let index = selected.firstIndex(of: identity) {
            selected.remove(at: index)
            // Deselecting the primary must clear it, or the draft ends up with a
            // primary that is not among the selections — which
            // `hasCompleteIdentitySelection` would reject with no visible cause.
            if primary == identity { primary = nil }
            refusedExtraPick = false
            AstraHaptics.selection()
            return
        }

        guard selected.count < required else {
            refusedExtraPick = true
            AstraHaptics.warning()
            return
        }

        selected.append(identity)
        refusedExtraPick = false
        AstraHaptics.selection()

        // Nominating the first pick as primary is a convenience, not a decision:
        // it means a user who agrees with the obvious default does nothing, and
        // the ranking rows are right there to change it. Only ever applied when
        // no primary has been chosen, so it never overwrites an explicit pick.
        if primary == nil { primary = identity }
    }
}

// MARK: - Cards

private struct IdentityCard: View {
    let identity: StyleIdentity
    /// 1-based position in the user's selection, or nil when unselected.
    let selectionOrder: Int?
    let isPrimary: Bool
    let toggle: () -> Void

    private var isSelected: Bool { selectionOrder != nil }

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                HStack(spacing: AstraSpacing.xxs) {
                    if let selectionOrder {
                        // The number, not just a tint — spec §19 again, and it
                        // also tells the user the order was recorded.
                        Text("\(selectionOrder)")
                            .astraText(.micro)
                            .foregroundStyle(AstraColor.textOnAccent)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(AstraColor.accentChampagne))
                    }
                    Spacer(minLength: 0)
                    if isPrimary {
                        Text("PRIMARY")
                            .astraText(.micro)
                            .foregroundStyle(AstraColor.accentChampagneAccessible)
                    }
                }
                .frame(height: 18)

                Text(identity.displayName)
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AstraSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: AstraRadius.card)
                    .fill(isSelected ? AstraColor.surfaceElevated : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AstraRadius.card)
                    .stroke(
                        isSelected ? AstraColor.accentChampagne : AstraColor.divider,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(identity.displayName)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("onboarding.identity.\(identity.rawValue)")
    }

    private var accessibilityValue: String {
        if isPrimary {
            return String(localized: "Selected, primary", comment: "Identity card VoiceOver value")
        }
        if let selectionOrder {
            return String(
                format: String(localized: "Selected, choice %d",
                               comment: "Identity card VoiceOver value"),
                selectionOrder
            )
        }
        return String(localized: "Not selected", comment: "Identity card VoiceOver value")
    }
}

private struct PrimaryChoiceRow: View {
    let identity: StyleIdentity
    let isPrimary: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: AstraSpacing.md) {
                Image(systemName: isPrimary ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(
                        isPrimary ? AstraColor.accentChampagneAccessible : AstraColor.textMuted
                    )
                    .accessibilityHidden(true)

                Text(identity.displayName)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textPrimary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AstraSpacing.md)
            .frame(minHeight: AstraSize.minTapTarget)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isPrimary ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("onboarding.primary.\(identity.rawValue)")
    }
}

#Preview("Identity") {
    @Previewable @State var selected: [StyleIdentity] = [.quietLuxury, .modernHeritage]
    @Previewable @State var primary: StyleIdentity? = .quietLuxury
    return ScrollView {
        OnboardingIdentityView(selected: $selected, primary: $primary)
            .padding(AstraSpacing.pagePadding)
    }
    .background(AstraColor.backgroundPrimary)
}
