//
//  KyraComposerView.swift
//  AstraStyle
//
//  The conversation composer: text field, on-device voice dictation,
//  attachment menu, staged-attachment chips, and send.
//
//  PHOTOS ARE STAGED AS BYTES, UPLOADED AT SEND. The chip the user can
//  still remove must not have already pushed his photo to storage — see
//  `KyraAttachmentDraft`'s header. A failed photo load from the library
//  is said out loud under the field rather than silently producing a
//  message with fewer attachments than he chose.
//
//  OFFLINE CLOSES THE COMPOSER AND SAYS WHY. Send is disabled and the
//  reason is stated in place — "Kyra needs a connection" — because a
//  generative request cannot be queued honestly (the answer depends on
//  conditions at the moment it runs; the P5-KYRA-18 decision in
//  AstraModelContainer.swift).
//

import PhotosUI
import SwiftUI

struct KyraComposerView: View {
    @Bindable var viewModel: KyraConversationViewModel

    @State private var isPickingPhoto = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var photoLoadFailed = false
    @State private var isPickingClosetItem = false
    @State private var isPickingOutfit = false
    @State private var isEnteringProductLink = false
    @State private var speechInput = KyraSpeechInputController()

    var body: some View {
        VStack(spacing: AstraSpacing.xs) {
            if !viewModel.attachments.isEmpty {
                stagedAttachments
            }
            inputRow
            if viewModel.isOffline {
                Text(String(
                    localized: "Kyra needs a connection. Your message will stay right here.",
                    comment: "Composer note while offline"
                ))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if photoLoadFailed {
                Text(String(
                    localized: "That photo couldn't be read from your library. Try another.",
                    comment: "Composer note when a picked photo failed to load"
                ))
                .astraText(.caption)
                .foregroundStyle(AstraColor.destructive)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            speechStatus
        }
        .padding(.horizontal, AstraSpacing.pagePadding)
        .padding(.vertical, AstraSpacing.sm)
        .background(AstraColor.backgroundSecondary.ignoresSafeArea(edges: .bottom))
        .photosPicker(isPresented: $isPickingPhoto, selection: $photoSelection, matching: .images)
        .onChange(of: photoSelection) {
            loadPickedPhoto()
        }
        .onChange(of: speechInput.transcript) { _, transcript in
            guard let transcript else { return }
            viewModel.draftText = transcript
        }
        .onDisappear { speechInput.cancel() }
        .sheet(isPresented: $isPickingClosetItem) {
            KyraClosetItemPickerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isPickingOutfit) {
            KyraOutfitPickerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isEnteringProductLink) {
            KyraProductLinkSheet { url in
                viewModel.attach(.productLink(url))
            }
        }
    }

    // MARK: - Rows

    private var stagedAttachments: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AstraSpacing.xs) {
                ForEach(viewModel.attachments) { draft in
                    attachmentChip(draft)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func attachmentChip(_ draft: KyraAttachmentDraft) -> some View {
        HStack(spacing: AstraSpacing.xxs) {
            Image(systemName: draft.iconName)
                .imageScale(.small)
            Text(draft.label)
                .astraText(.caption)
                .lineLimit(1)
            Button {
                viewModel.removeAttachment(id: draft.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.small)
            }
            .accessibilityLabel(Text(String(
                localized: "Remove \(draft.label)",
                comment: "Removes a staged Kyra attachment"
            )))
        }
        .foregroundStyle(AstraColor.textSecondary)
        .padding(.horizontal, AstraSpacing.sm)
        .padding(.vertical, AstraSpacing.xxs)
        .background(Capsule(style: .continuous).strokeBorder(AstraColor.divider, lineWidth: 1))
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: AstraSpacing.sm) {
            attachmentMenu
            TextField(
                String(localized: "Ask Kyra anything about your style", comment: "Composer placeholder"),
                text: $viewModel.draftText,
                axis: .vertical
            )
            .lineLimit(1...4)
            .astraText(.body)
            .foregroundStyle(AstraColor.textPrimary)
            .padding(.horizontal, AstraSpacing.md)
            .padding(.vertical, AstraSpacing.xs)
            .frame(minHeight: AstraSize.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: AstraSpacing.buttonRadius, style: .continuous)
                    .fill(AstraColor.backgroundPrimary)
            )
            .disabled(viewModel.isOffline || speechInput.state != .idle)
            .accessibilityIdentifier("kyra.composer.field")
            voiceButton
            sendButton
        }
    }

    private var attachmentMenu: some View {
        Menu {
            Button {
                isPickingPhoto = true
            } label: {
                Label(String(localized: "Photo", comment: "Attachment kind"), systemImage: "photo")
            }
            Button {
                isEnteringProductLink = true
            } label: {
                Label(String(localized: "Product Link", comment: "Attachment kind"), systemImage: "link")
            }
            Button {
                isPickingClosetItem = true
            } label: {
                Label(String(localized: "Closet Item", comment: "Attachment kind"), systemImage: "tshirt")
            }
            Button {
                isPickingOutfit = true
            } label: {
                Label(String(localized: "Outfit", comment: "Attachment kind"), systemImage: "square.grid.2x2")
            }
        } label: {
            Image(systemName: "plus.circle")
                .astraIcon(.display)
                .foregroundStyle(AstraColor.accentChampagneAccessible)
                .frame(width: AstraSize.minTapTarget, height: AstraSize.minTapTarget)
        }
        .disabled(viewModel.isOffline || viewModel.isSending || speechInput.state != .idle)
        .accessibilityLabel(Text(String(localized: "Attach", comment: "Opens the attachment menu")))
        .accessibilityIdentifier("kyra.composer.attach")
    }

    private var sendButton: some View {
        Button {
            Task { await viewModel.sendDraft() }
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .astraIcon(.display)
                .foregroundStyle(
                    viewModel.canSendDraft
                        ? AstraColor.accentChampagneAccessible
                        : AstraColor.textMuted
                )
                .frame(width: AstraSize.minTapTarget, height: AstraSize.minTapTarget)
        }
        .disabled(!viewModel.canSendDraft || speechInput.state != .idle)
        .accessibilityLabel(Text(String(localized: "Send", comment: "Sends the composed Kyra message")))
        .accessibilityIdentifier("kyra.composer.send")
    }

    private var voiceButton: some View {
        Button {
            Task { await speechInput.toggle() }
        } label: {
            Image(systemName: speechInput.state == .recording ? "stop.circle.fill" : "mic.circle")
                .astraIcon(.display)
                .foregroundStyle(
                    speechInput.state == .recording
                        ? AstraColor.destructive
                        : AstraColor.accentChampagneAccessible
                )
                .frame(width: AstraSize.minTapTarget, height: AstraSize.minTapTarget)
        }
        .disabled(
            viewModel.isOffline
                || viewModel.isSending
                || speechInput.state == .requestingPermission
                || speechInput.state == .transcribing
        )
        .accessibilityLabel(Text(
            speechInput.state == .recording
                ? String(localized: "Stop recording", comment: "Stops voice input and transcribes it")
                : String(localized: "Dictate to Kyra", comment: "Starts voice input")
        ))
        .accessibilityHint(Text(String(
            localized: "Your speech is transcribed on this device and added to the message field.",
            comment: "Privacy hint for voice input"
        )))
        .accessibilityIdentifier("kyra.composer.voice")
    }

    @ViewBuilder
    private var speechStatus: some View {
        switch speechInput.state {
        case .idle:
            if let errorMessage = speechInput.errorMessage {
                HStack(alignment: .top, spacing: AstraSpacing.xs) {
                    Text(errorMessage)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.destructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(String(localized: "Dismiss", comment: "Dismiss voice input status")) {
                        speechInput.clearError()
                    }
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
                    .accessibilityIdentifier("kyra.composer.voice.dismissError")
                }
            }
        case .requestingPermission:
            Text(String(localized: "Preparing voice input…", comment: "Voice permissions are being requested"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .recording:
            Text(String(localized: "Listening. Tap stop when you're done.", comment: "Voice recording state"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.accentChampagneAccessible)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("kyra.composer.voice.recording")
        case .transcribing:
            HStack(spacing: AstraSpacing.xs) {
                ProgressView().tint(AstraColor.accentChampagne)
                Text(String(localized: "Transcribing on this device…", comment: "Voice transcription state"))
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadPickedPhoto() {
        guard let item = photoSelection else { return }
        photoSelection = nil
        photoLoadFailed = false
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                viewModel.attach(.photo(data))
            } else {
                // Said out loud, not swallowed: a silently-missing
                // attachment would send a different message than the one
                // the user composed.
                photoLoadFailed = true
            }
        }
    }
}
