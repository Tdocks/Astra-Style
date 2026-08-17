//
//  KyraMessageRowView.swift
//  AstraStyle
//
//  One transcript row: a user bubble (with its attachment chips and, when
//  the send failed, a visible failure with retry), or Kyra's message with
//  its cards, memory notes, and suggested actions.
//
//  A FAILED SEND STAYS ON SCREEN, MARKED. The alternative — dropping the
//  bubble back into the composer, or worse, leaving it looking sent — is
//  the "silently lost" failure P5-KYRA-18's acceptance criterion names.
//  The retry appears only while it can succeed (spec §21): offline, the
//  row states the blocker instead.
//
//  SUGGESTED ACTIONS ARE FILTERED THROUGH `canPerform` BEFORE RENDERING —
//  see the view model's action extension for the reasoning; this view
//  never draws a button the app cannot honor.
//

import SwiftUI

struct KyraMessageRowView: View {
    let entry: KyraTranscriptEntry
    var viewModel: KyraConversationViewModel

    var body: some View {
        if entry.role == .user {
            userRow
        } else {
            assistantRow
        }
    }

    // MARK: - User

    private var userRow: some View {
        VStack(alignment: .trailing, spacing: AstraSpacing.xs) {
            if !entry.attachmentLabels.isEmpty {
                attachmentEcho
            }
            Text(entry.text)
                .astraText(.body)
                .foregroundStyle(AstraColor.textPrimary)
                .padding(AstraSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: AstraSpacing.cardRadius, style: .continuous)
                        .fill(AstraColor.backgroundSecondary)
                )
                .accessibilityIdentifier("kyra.message.user")
            if let failure = entry.sendFailure {
                sendFailureRow(failure)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var attachmentEcho: some View {
        HStack(spacing: AstraSpacing.xs) {
            ForEach(entry.attachmentLabels, id: \.self) { label in
                Text(label)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
                    .padding(.horizontal, AstraSpacing.sm)
                    .padding(.vertical, AstraSpacing.xxs)
                    .background(Capsule(style: .continuous).strokeBorder(AstraColor.divider, lineWidth: 1))
            }
        }
    }

    private func sendFailureRow(_ failure: AstraError) -> some View {
        HStack(spacing: AstraSpacing.xs) {
            Image(systemName: "exclamationmark.circle")
                .astraIcon(.emphasis)
                .foregroundStyle(AstraColor.destructive)
                .accessibilityHidden(true)
            Text(String(localized: "Didn't send.", comment: "Marker on a Kyra message that failed to send"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.destructive)
            if viewModel.isOffline {
                Text(String(
                    localized: "Waiting for a connection.",
                    comment: "Shown instead of retry while offline"
                ))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
            } else {
                Button(String(localized: "Retry", comment: "Retries a failed Kyra message")) {
                    Task { await viewModel.retrySend(entryID: entry.id) }
                }
                .buttonStyle(.astraTertiary)
                .accessibilityIdentifier("kyra.message.retry")
            }
        }
    }

    // MARK: - Kyra

    private var assistantRow: some View {
        HStack(alignment: .top, spacing: AstraSpacing.sm) {
            AstraMonogram(size: AstraSpacing.xl)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                Text(entry.text)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("kyra.message.assistant")
                ForEach(entry.cards) { card in
                    KyraCardView(card: card, entryID: entry.id, viewModel: viewModel)
                }
                if !performableActions.isEmpty {
                    actionRow
                }
                ForEach(entry.memoryNotes, id: \.self) { note in
                    memoryNote(note)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var performableActions: [KyraSuggestedAction] {
        entry.suggestedActions.filter { viewModel.canPerform($0, in: entry) }
    }

    private var actionRow: some View {
        AstraWrappingHStack(spacing: AstraSpacing.xs) {
            ForEach(performableActions, id: \.id) { action in
                KyraActionButton(action: action, entryID: entry.id, viewModel: viewModel)
            }
        }
    }

    /// A memory proposal surfaced the way the system prompt promises it
    /// will be: "a visible, removable note". Visible happens here; removal
    /// lives with the memory inspector (P5-KYRA-17), which is where the
    /// note directs by name.
    private func memoryNote(_ note: String) -> some View {
        HStack(alignment: .top, spacing: AstraSpacing.xs) {
            Image(systemName: "bookmark")
                .astraIcon(.emphasis)
                .foregroundStyle(AstraColor.accentChampagneAccessible)
                .accessibilityHidden(true)
            Text(String(
                localized: "Noted: \(note) — manage what Kyra remembers in Profile.",
                comment: "A durable preference Kyra saved this turn"
            ))
            .astraText(.caption)
            .foregroundStyle(AstraColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("kyra.memoryNote")
    }
}
