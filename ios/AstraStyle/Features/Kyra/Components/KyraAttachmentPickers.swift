//
//  KyraAttachmentPickers.swift
//  AstraStyle
//
//  The three sheets behind the composer's attachment menu: closet item,
//  outfit, and product link. Same shape as `OutfitItemPickerSheet`
//  (Features/Outfits): the sheet renders state the view model owns —
//  except that here the load is triggered by the sheet's appearance,
//  because most sends never attach anything and the choices would
//  otherwise be fetched for every conversation.
//
//  An empty closet and a failed fetch render differently on purpose:
//  `AttachmentChoices` is a tri-state so "you haven't added anything yet"
//  is never shown over what is actually a network error, and the error's
//  retry is offered only while retrying can succeed (spec §21).
//

import SwiftUI

struct KyraClosetItemPickerSheet: View {
    var viewModel: KyraConversationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            KyraPickerContent(
                choices: viewModel.attachmentChoices,
                isOffline: viewModel.isOffline,
                emptyText: String(
                    localized: "Nothing in your closet yet — scan or add a piece first.",
                    comment: "Closet-item attachment picker with an empty closet"
                ),
                select: { closet, _ in closet },
                onRetry: { await viewModel.loadAttachmentChoices() },
                row: { item in
                    Button {
                        viewModel.attach(.closetItem(item))
                        dismiss()
                    } label: {
                        KyraPickerRow(title: item.name, subtitle: item.brand ?? item.category.displayName)
                    }
                    .accessibilityIdentifier("kyra.picker.closetItem.\(item.id.uuidString)")
                }
            )
            .navigationTitle(String(localized: "Closet Item", comment: "Attachment picker title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { KyraPickerCloseButton() }
        }
        .presentationBackground(AstraColor.backgroundPrimary)
        .task { await viewModel.loadAttachmentChoices() }
    }
}

struct KyraOutfitPickerSheet: View {
    var viewModel: KyraConversationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            KyraPickerContent(
                choices: viewModel.attachmentChoices,
                isOffline: viewModel.isOffline,
                emptyText: String(
                    localized: "No saved outfits yet — Kyra builds them as your closet grows.",
                    comment: "Outfit attachment picker with no saved outfits"
                ),
                select: { _, outfits in outfits },
                onRetry: { await viewModel.loadAttachmentChoices() },
                row: { outfit in
                    Button {
                        viewModel.attach(.outfit(outfit))
                        dismiss()
                    } label: {
                        KyraPickerRow(title: outfit.name, subtitle: outfit.occasionTags.first)
                    }
                    .accessibilityIdentifier("kyra.picker.outfit.\(outfit.id.uuidString)")
                }
            )
            .navigationTitle(String(localized: "Outfit", comment: "Attachment picker title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { KyraPickerCloseButton() }
        }
        .presentationBackground(AstraColor.backgroundPrimary)
        .task { await viewModel.loadAttachmentChoices() }
    }
}

// MARK: - Product link entry

/// A pasted retailer URL, validated for shape only (scheme + host) — the
/// real extraction happens server-side when Kyra analyzes it. Attach stays
/// disabled until the text parses, so the button can never submit a
/// string the wire shape cannot carry.
struct KyraProductLinkSheet: View {
    let onAttach: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var linkText = ""

    private var parsedURL: URL? {
        guard let url = URL(string: linkText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host() != nil else { return nil }
        return url
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                Text(String(
                    localized: "Paste a product page and Kyra will weigh it against your closet.",
                    comment: "Product link sheet explainer"
                ))
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                TextField(String(localized: "https://…", comment: "Product link placeholder"), text: $linkText)
                    .astraText(.body)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(AstraSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: AstraSpacing.buttonRadius, style: .continuous)
                            .fill(AstraColor.backgroundSecondary)
                    )
                    .accessibilityIdentifier("kyra.productLink.field")
                AstraButton(title: String(localized: "Attach Link", comment: "Attaches the pasted product link")) {
                    guard let url = parsedURL else { return }
                    onAttach(url)
                    dismiss()
                }
                .disabled(parsedURL == nil)
                .accessibilityIdentifier("kyra.productLink.attach")
                Spacer()
            }
            .padding(AstraSpacing.pagePadding)
            .background(AstraColor.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(String(localized: "Product Link", comment: "Attachment picker title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { KyraPickerCloseButton() }
        }
        .presentationBackground(AstraColor.backgroundPrimary)
        .presentationDetents([.medium])
    }
}

// MARK: - Shared picker chrome

struct KyraPickerContent<Item: Identifiable, Row: View>: View {
    let choices: KyraConversationViewModel.AttachmentChoices
    let isOffline: Bool
    let emptyText: String
    let select: ([ClosetItem], [Outfit]) -> [Item]
    let onRetry: () async -> Void
    let row: (Item) -> Row

    init(
        choices: KyraConversationViewModel.AttachmentChoices,
        isOffline: Bool,
        emptyText: String,
        select: @escaping ([ClosetItem], [Outfit]) -> [Item],
        onRetry: @escaping () async -> Void,
        @ViewBuilder row: @escaping (Item) -> Row
    ) {
        self.choices = choices
        self.isOffline = isOffline
        self.emptyText = emptyText
        self.select = select
        self.onRetry = onRetry
        self.row = row
    }

    var body: some View {
        Group {
            switch choices {
            case .loading:
                ProgressView()
                    .tint(AstraColor.accentChampagne)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error):
                failed(error)
            case .loaded(let closet, let outfits):
                loaded(items: select(closet, outfits))
            }
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
    }

    @ViewBuilder
    private func loaded(items: [Item]) -> some View {
        if items.isEmpty {
            Text(emptyText)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(AstraSpacing.pagePadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AstraSpacing.xs) {
                    ForEach(items) { item in
                        row(item)
                    }
                }
                .padding(AstraSpacing.pagePadding)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func failed(_ error: AstraError) -> some View {
        VStack(spacing: AstraSpacing.md) {
            Text(error.message)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)
            if isOffline {
                Text(String(
                    localized: "You're offline — try again once you're connected.",
                    comment: "Attachment picker failure while offline"
                ))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
            } else {
                Button(String(localized: "Try Again", comment: "Retries loading attachment choices")) {
                    Task { await onRetry() }
                }
                .buttonStyle(.astraSecondary)
            }
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct KyraPickerRow: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            Text(title)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textPrimary)
                .multilineTextAlignment(.leading)
            if let subtitle {
                Text(subtitle)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The shared Close control, so all three sheets dismiss the same way.
struct KyraPickerCloseButton: ToolbarContent {
    @Environment(\.dismiss) private var dismiss

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: "Close", comment: "Dismisses an attachment picker")) {
                dismiss()
            }
        }
    }
}
