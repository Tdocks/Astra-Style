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
//  There is deliberately no minimum. A man who wants none of these is telling us
//  something true, and a forced pick would record noise as signal.
//

import SwiftUI

struct OnboardingGoalsView: View {
    @Binding var selected: Set<StyleGoal>

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            ForEach(StyleGoal.allCases) { goal in
                GoalRow(
                    goal: goal,
                    isSelected: selected.contains(goal),
                    toggle: { toggle(goal) }
                )
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
                        isSelected ? AstraColor.accentChampagne : AstraColor.divider,
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
