//
//  KyraConversationView.swift
//  AstraStyle
//
//  The Kyra conversation screen (spec §6.20, P5-KYRA-13): transcript,
//  composer, suggested prompts, and every state spec §21 asks for —
//  loading (history fetch), empty (a new conversation, whose content IS
//  the suggested prompts), offline (a stated condition with the composer
//  closed, not a queue), a recoverable load error whose retry appears only
//  while retrying can succeed, and the in-flight thinking state.
//
//  THERE IS NO FABRICATED GREETING. An empty conversation shows Kyra's
//  mark and the prompts, not a scripted "Hi, I'm Kyra!" bubble styled as a
//  message: every bubble in the transcript is a message that actually
//  exists (locally echoed or server-persisted), because a bubble that was
//  never sent teaches the user that bubbles here might be theatre.
//
//  VOICE INPUT IS ABSENT, NOT STUBBED. Spec §6.20 lists voice among the
//  input kinds; P5-KYRA-16 owns it (it is the one input that needs a new
//  permission, which is why the completion plan sequences it last). A mic
//  button that opens an apology would be §22's dead button, so the
//  composer simply doesn't draw one until the feature exists.
//

import SwiftUI

public struct KyraConversationView: View {
    @State private var viewModel: KyraConversationViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(viewModel: KyraConversationViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ZStack {
            AstraColor.backgroundPrimary.ignoresSafeArea()
            content
        }
        .navigationTitle(String(localized: "Kyra", comment: "Conversation screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Close", comment: "Dismisses the Kyra conversation")) {
                    dismiss()
                }
                .accessibilityIdentifier("kyra.close")
            }
        }
        .task { await viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .accessibilityIdentifier("kyra.conversation")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.historyState {
        case .loading:
            loadingState
        case .failed(let error):
            failedState(error)
        case .loaded:
            conversation
        }
    }

    // MARK: - History states

    private var loadingState: some View {
        VStack(spacing: AstraSpacing.md) {
            ProgressView()
                .tint(AstraColor.accentChampagne)
            Text(String(localized: "Opening the conversation…", comment: "Kyra history loading state"))
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Recoverable error with a retry offered only while retrying can
    /// succeed (spec §21): while offline the same screen states the real
    /// blocker instead of dangling a button that must fail.
    private func failedState(_ error: AstraError) -> some View {
        VStack(spacing: AstraSpacing.md) {
            Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                .astraIcon(.display)
                .foregroundStyle(AstraColor.textMuted)
                .accessibilityHidden(true)
            Text(error.message)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)
            if viewModel.isOffline {
                Text(String(
                    localized: "You're offline — this will be retryable once you're back on a connection.",
                    comment: "Kyra history load failure while offline"
                ))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
                .multilineTextAlignment(.center)
            } else {
                Button(String(localized: "Try Again", comment: "Retries loading the Kyra conversation")) {
                    Task { await viewModel.reloadHistory() }
                }
                .buttonStyle(.astraSecondary)
                .accessibilityIdentifier("kyra.history.retry")
            }
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Conversation

    private var conversation: some View {
        VStack(spacing: 0) {
            if viewModel.isOffline {
                offlineBanner
            }
            transcript
            if let note = viewModel.actionNote {
                actionNote(note)
            }
            KyraComposerView(viewModel: viewModel)
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AstraSpacing.lg) {
                    if viewModel.showsSuggestedPrompts {
                        emptyState
                    }
                    ForEach(viewModel.entries) { entry in
                        KyraMessageRowView(entry: entry, viewModel: viewModel)
                            .id(entry.id)
                    }
                    if viewModel.isSending {
                        KyraThinkingIndicatorView()
                            .id(Self.thinkingRowID)
                    }
                }
                .padding(AstraSpacing.pagePadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.entries.count) {
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.isSending) {
                scrollToBottom(proxy)
            }
        }
    }

    /// Stable id for the thinking row so auto-scroll can target it.
    private static let thinkingRowID = "kyra.thinking.row"

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(AstraMotion.aware(AstraMotion.standard, reduceMotion: reduceMotion)) {
            if viewModel.isSending {
                proxy.scrollTo(Self.thinkingRowID, anchor: .bottom)
            } else if let lastEntryID = viewModel.entries.last?.id {
                proxy.scrollTo(lastEntryID, anchor: .bottom)
            }
        }
    }

    // MARK: - Empty state (spec §21) — its content is the prompts

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.lg) {
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                AstraMonogram(size: AstraSize.minTapTarget)
                    .accessibilityHidden(true)
                Text(String(localized: "Ask Kyra", comment: "Empty conversation title"))
                    .astraText(.title2)
                    .foregroundStyle(AstraColor.textPrimary)
                Text(String(
                    localized: "An outfit for tonight, a purchase you're unsure about, a suitcase to pack — ask about any of it.",
                    comment: "Empty conversation subtitle describing what Kyra helps with"
                ))
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            KyraSuggestedPromptsView { prompt in
                Task { await viewModel.send(prompt: prompt) }
            }
        }
        .accessibilityIdentifier("kyra.empty")
    }

    // MARK: - Ambient rows

    private var offlineBanner: some View {
        HStack(spacing: AstraSpacing.xs) {
            Image(systemName: "wifi.slash")
                .astraIcon(.emphasis)
                .accessibilityHidden(true)
            Text(String(
                localized: "You're offline. Kyra needs a connection.",
                comment: "Offline banner on the Kyra conversation"
            ))
            .astraText(.caption)
        }
        .foregroundStyle(AstraColor.warningAmber)
        .frame(maxWidth: .infinity)
        .padding(.vertical, AstraSpacing.xs)
        .background(AstraColor.backgroundSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("kyra.offlineBanner")
    }

    private func actionNote(_ note: String) -> some View {
        Text(note)
            .astraText(.caption)
            .foregroundStyle(AstraColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AstraSpacing.pagePadding)
            .padding(.vertical, AstraSpacing.xs)
            .accessibilityIdentifier("kyra.actionNote")
    }
}
