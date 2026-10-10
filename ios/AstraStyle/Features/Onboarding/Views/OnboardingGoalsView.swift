//
//  OnboardingGoalsView.swift
//  AstraStyle
//
//  Spec §6.4 — Style goals. Multi-select over eight options.
//
//  Each option shows what selecting it actually changes (`StyleGoal.effect`),
//  because a list of eight abstract goals invites selecting all eight — and a
//  user who picks everything has told us nothing. Making the consequence
//  visible turns it into a real choice.
//
//  At least one goal is required by §6.4. The screen says so before the user
//  reaches the disabled Continue control.
//

import SwiftUI

struct OnboardingGoalsView: View {
    @Binding var selected: Set<StyleGoal>

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                ForEach(StyleGoal.allCases) { goal in
                    GoalRow(
                        goal: goal,
                        isSelected: selected.contains(goal),
                        toggle: { toggle(goal) }
                    )
                }
            }

            if selected.isEmpty {
                Text(String(
                    localized: "Choose at least one goal to continue.",
                    comment: "Required selection hint on the style goals onboarding step"
                ))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
                .accessibilityIdentifier("onboarding.goals.requirement")
            }
        }
    }

    private func toggle(_ goal: StyleGoal) {
        if selected.contains(goal) {
            selected.remove(goal)
        } else {
            selected.insert(goal)
        }
        AstraHaptics.selection()
    }
}

private struct GoalRow: View {
    let goal: StyleGoal
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: AstraSpacing.md) {
                // A filled checkmark plus a border change, not colour alone —
                // spec §19 forbids encoding meaning by colour only.
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        isSelected ? AstraColor.accentChampagneAccessible : AstraColor.textMuted
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text(goal.displayName)
                        .astraText(.headline)
                        .foregroundStyle(AstraColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(goal.effect)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(AstraSpacing.md)
            .frame(minHeight: AstraSize.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: AstraRadius.card)
                    .fill(isSelected ? AstraColor.surfaceElevated : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AstraRadius.card)
                    .stroke(
                        isSelected ? AstraColor.accentChampagneAccessible : AstraColor.divider,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        // One combined element with an explicit trait, so VoiceOver announces
        // "<goal>, <effect>, selected" rather than reading the checkmark, the
        // title and the caption as three separate stops.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("onboarding.goal.\(goal.rawValue)")
    }
}

#Preview("Goals") {
    @Previewable @State var selected: Set<StyleGoal> = [.shopMoreIntelligently]
    return ScrollView {
        OnboardingGoalsView(selected: $selected)
            .padding(AstraSpacing.pagePadding)
    }
    .background(AstraColor.backgroundPrimary)
}
