//
//  KyraSuggestedPromptsView.swift
//  AstraStyle
//
//  The suggested-prompt row (spec §6.20, P5-KYRA-15). Each chip SENDS its
//  prompt — the ticket's one acceptance criterion is that these are real
//  messages to `/kyra/respond`, not decoration — via the same view-model
//  path as typed text, so there is no second send implementation to
//  drift.
//
//  Laid out as a leading column rather than a wrapping row: the prompts
//  are full sentences, and at accessibility type sizes a wrap layout
//  degenerates into one chip per line anyway — the column is that end
//  state chosen on purpose, stable at every size.
//

import SwiftUI

struct KyraSuggestedPromptsView: View {
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            ForEach(Array(KyraConversationViewModel.suggestedPrompts.enumerated()), id: \.offset) { index, prompt in
                AstraChip(prompt, isSelected: false) {
                    onSelect(prompt)
                }
                .accessibilityIdentifier("kyra.prompt.\(index)")
            }
        }
        .accessibilityIdentifier("kyra.prompts")
    }
}
