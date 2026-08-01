//
//  ClosetItemDetailView.swift
//  AstraStyle
//
//  Spec §6.15 "Item detail". Every field the model can answer, the four
//  actions, and nothing this build cannot honestly show.
//
//  No network call happens in this file — everything routes through
//  `ClosetItemDetailViewModel`, per CLAUDE.md's "no network calls in
//  views" rule extended to the view-model boundary.
//
//  INSIGHTS ARE NOT HERE. §6.15's "Best pairings / Outfit gallery /
//  Redundancy score / Replacement suggestion" block is a separate ticket
//  and depends on the Phase 4 compatibility engine. This screen leaves
//  room for it below the fields rather than stubbing it.
//
//  HOW EMPTY FIELDS ARE TREATED, AND WHY. A row whose value is absent is
//  OMITTED, not rendered as "Brand —". An item scanned in ten seconds has
//  four of fourteen optional fields filled, and nine dashes down the page
//  reads as a broken screen rather than as an incomplete record. The
//  exceptions are the four rows where absence IS the information and
//  hiding it would hide the point: wear count, last worn, cost per wear
//  and laundry state always render, with copy that says what the blank
//  means. One quiet affordance at the bottom names how many fields are
//  still empty and opens the editor, so an under-filled item is never
//  silently indistinguishable from a complete one.
//

import SwiftUI

public struct ClosetItemDetailView: View {
    @State private var viewModel: ClosetItemDetailViewModel
    @State private var editingItem: ClosetItem?
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: ClosetItemDetailViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.xl) {
                if viewModel.isOffline, viewModel.state.detail != nil {
                    ClosetItemOfflineBanner()
                }
                content
            }
            .padding(.horizontal, AstraSpacing.pagePadding)
            .padding(.vertical, AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .refreshable { await viewModel.refresh() }
        .navigationTitle(viewModel.state.detail?.item.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
        // The item is gone from every default closet view the moment the
        // archive succeeds, so staying on its detail screen would leave the
        // user looking at something he can no longer navigate back to.
        .onChange(of: viewModel.didArchive) { _, didArchive in
            if didArchive { dismiss() }
        }
        .onChange(of: viewModel.savedEditCount) { _, _ in
            editingItem = nil
        }
        .sheet(item: $editingItem) { item in
            editorSheet(for: item)
        }
        .alert(
            Text(actionFailureTitle),
            isPresented: actionErrorPresented,
            presenting: viewModel.actionError
        ) { _ in
            Button(dismissTitle) { viewModel.clearActionError() }
        } message: { error in
            // `AstraError.message` is already user-facing copy — rendered
            // as-is rather than wrapped in a second sentence of our own.
            Text(error.message)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ClosetItemDetailSkeleton()

        case .failed(let error):
            ClosetItemDetailErrorView(error: error) {
                Task { await viewModel.refresh() }
            }

        case .loaded(let detail), .empty(let detail):
            ClosetItemDetailContent(
                viewModel: viewModel,
                detail: detail,
                onEdit: { editingItem = detail.item }
            )
        }
    }

    /// The Edit action, presented as a sheet (spec §6.15 "Edit").
    ///
    /// The `NavigationStack` and its Cancel button are added HERE, not by
    /// `ClosetItemFormView` — that view deliberately owns no bar, because
    /// it is also pushed onto a stack that already has one. A sheet with no
    /// cancel affordance is dismissible only by swipe, which is invisible
    /// to VoiceOver and to Switch Control, so the presenting surface owes
    /// it one.
    private func editorSheet(for item: ClosetItem) -> some View {
        NavigationStack {
            ClosetItemFormView(viewModel: makeEditorViewModel(for: item))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(cancelTitle) { editingItem = nil }
                    }
                }
        }
    }

    /// Builds the add/edit form's view model for the Edit action.
    ///
    /// `ClosetItemFormView` stores what it is handed in `@State`, so the
    /// throwaway instance this makes on a re-render of the sheet's body is
    /// discarded rather than replacing the live one — the same contract
    /// `HomeView` relies on.
    ///
    /// The `onSaved` closure captures ONLY the view model, never `self`.
    /// The view model is a `@MainActor` class and therefore `Sendable`; a
    /// `View` struct is not, and capturing one in a `@Sendable` closure is
    /// the kind of thing Swift 6 strict concurrency exists to reject.
    /// Closing the sheet is driven by `savedEditCount` instead.
    private func makeEditorViewModel(for item: ClosetItem) -> ClosetItemFormViewModel {
        let editor = ClosetItemFormViewModel.editing(item: item, closetRepository: viewModel.closetRepository)
        editor.onSaved = { [viewModel] saved in
            viewModel.applyEditedItem(saved)
        }
        return editor
    }

    private var actionErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.actionError != nil },
            set: { isPresented in
                if !isPresented { viewModel.clearActionError() }
            }
        )
    }

    private var actionFailureTitle: String {
        String(localized: "That didn't save", comment: "Title of the alert shown when a closet item action fails")
    }

    private var dismissTitle: String {
        String(localized: "OK", comment: "Dismisses an alert")
    }

    private var cancelTitle: String {
        String(localized: "Cancel", comment: "Closes the garment editor without saving")
    }
}

// MARK: - Loaded content

private struct ClosetItemDetailContent: View {
    let viewModel: ClosetItemDetailViewModel
    let detail: ClosetItemDetailViewModel.ItemDetail
    let onEdit: () -> Void

    private var item: ClosetItem { detail.item }

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xl) {
            ClosetItemHeroSection(detail: detail)

            header

            ClosetItemActionRow(
                laundryState: item.laundryState,
                isMarkingWorn: viewModel.isMarkingWorn,
                isUpdatingLaundryState: viewModel.isUpdatingLaundryState,
                isArchiving: viewModel.isArchiving,
                onMarkWorn: markWorn,
                onSetLaundryState: setLaundryState,
                onEdit: onEdit,
                onArchive: archive
            )

            ClosetItemPieceSection(item: item)

            ClosetItemWearSection(
                item: item,
                isUpdatingLaundryState: viewModel.isUpdatingLaundryState,
                onSetLaundryState: setLaundryState
            )

            ClosetItemPurchaseSection(item: item)

            unfilledDetailsPrompt
        }
    }

    /// §6.15's "Category and subtype" is carried by the eyebrow above the
    /// name rather than by two more rows further down. It is the first
    /// thing a garment is — putting it in the header states it once, in
    /// the place the eye already is, instead of twice.
    private var header: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            Text(categoryLine)
                .astraText(.micro)
                .foregroundStyle(AstraColor.accentChampagneAccessible)
            Text(item.name)
                .astraText(.title1)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement()
        .accessibilityLabel(Text(item.name))
        .accessibilityValue(Text(categoryLine))
        .accessibilityAddTraits(.isHeader)
    }

    private var categoryLine: String {
        guard let subcategory = item.subcategory, !subcategory.isEmpty else {
            return item.category.displayName
        }
        return "\(item.category.displayName) · \(subcategory)"
    }

    /// One affordance, shown only when there is something to fill in.
    /// It opens the same editor the action row's Edit button does — this
    /// is a shortcut with a count on it, not a second, competing path.
    @ViewBuilder
    private var unfilledDetailsPrompt: some View {
        let unfilled = ClosetItemDetailCopy.unfilledDetailCount(for: item)
        if unfilled > 0 {
            Button(action: onEdit) {
                Text(ClosetItemDetailCopy.unfilledDetailPrompt(count: unfilled))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.astraTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHint(Text(unfilledDetailsHint))
        }
    }

    private var unfilledDetailsHint: String {
        String(localized: "Opens the editor so you can fill them in", comment: "Accessibility hint on the unfilled-details shortcut")
    }

    // MARK: - Actions

    /// Haptics live here rather than in the view model so that a unit test
    /// of `markWorn()` never reaches for the Taptic Engine — and so the
    /// "saved" feedback fires on the OUTCOME rather than on the tap. A
    /// success haptic at tap time would confirm a save that had not
    /// happened yet and might not happen at all.
    private func markWorn() {
        Task {
            await viewModel.markWorn()
            if viewModel.actionError == nil {
                AstraHaptics.success()
            }
        }
    }

    private func setLaundryState(_ state: LaundryState) {
        Task { await viewModel.setLaundryState(state) }
    }

    /// `AstraHaptics.warning()` already fired when the confirmation was
    /// raised (spec §3: warning PRECEDES a destructive action), so this
    /// path does not fire a second one.
    private func archive() {
        Task { await viewModel.archive() }
    }
}

// MARK: - Photographs

/// §6.15's "Normalized cutout image" and "User photos", in that order.
///
/// The hero is NOT downsampled (`thumbnail: nil`): it is drawn at close to
/// the full width of the screen, and `ImageDownsampling`'s tile sizes would
/// make it visibly soft. The strip beneath it is, because those are 80 pt
/// squares and decoding a 4032 × 3024 capture at full size to draw one is
/// the memory warning `AstraRemoteImage`'s header describes.
private struct ClosetItemHeroSection: View {
    // 20 × the 4 pt base unit. There is no thumbnail-size token in
    // `AstraSize` yet and this file may not add one; promote it to
    // `AstraSize.photoStripThumbnail` when a second surface needs the same
    // square. Deliberately not scaled by Dynamic Type — a photograph does
    // not get more legible when the text around it grows.
    private static let stripThumbnailSize = AstraSpacing.unit * 20

    let detail: ClosetItemDetailViewModel.ItemDetail

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraRemoteImage(
                url: detail.heroImage.flatMap { detail.url(for: $0) },
                // 4:5 is `AstraRemoteImage`'s own documented editorial
                // card ratio, as used by the Home hero outfit card.
                aspectRatio: 4.0 / 5.0,
                thumbnail: nil,
                accessibilityDescription: heroDescription
            )

            if detail.images.isEmpty {
                Text(noPhotosCopy)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !detail.userPhotos.isEmpty {
                photoStrip
            }
        }
    }

    private var photoStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AstraSpacing.xs) {
                ForEach(Array(detail.userPhotos.enumerated()), id: \.element.id) { index, image in
                    AstraRemoteImage(
                        url: detail.url(for: image),
                        aspectRatio: 1,
                        thumbnail: .closetGridTile,
                        accessibilityDescription: photoDescription(index: index)
                    )
                    .frame(width: Self.stripThumbnailSize, height: Self.stripThumbnailSize)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var heroDescription: String {
        String(localized: "Photograph of \(detail.item.name)", comment: "Accessibility description of the item detail hero image")
    }

    private func photoDescription(index: Int) -> String {
        String(
            localized: "Photo \(index + 2) of \(detail.item.name)",
            comment: "Accessibility description of an additional garment photo; the hero image is photo 1"
        )
    }

    private var noPhotosCopy: String {
        String(localized: "No photos of this piece yet.", comment: "Shown when a closet item has no images on file")
    }
}

// MARK: - Non-content states

/// Spec §7: cached closet content stays viewable offline, and edits queue
/// rather than fail — so this says what will happen rather than telling the
/// user to come back later.
private struct ClosetItemOfflineBanner: View {
    var body: some View {
        HStack(spacing: AstraSpacing.xs) {
            Image(systemName: "wifi.slash")
                .astraIcon(.inline)
                .foregroundStyle(AstraColor.warningAmber)
                .accessibilityHidden(true)

            Text(copy)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AstraSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AstraRadius.small, style: .continuous)
                .fill(AstraColor.backgroundSecondary)
        )
        .accessibilityElement()
        .accessibilityLabel(Text(copy))
    }

    private var copy: String {
        String(localized: "You're offline. Changes to this piece will sync when you're back.", comment: "Offline banner on the item detail screen")
    }
}

private struct ClosetItemDetailSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                .fill(AstraColor.surfaceElevated)
                .aspectRatio(4.0 / 5.0, contentMode: .fit)

            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: AstraRadius.small, style: .continuous)
                    .fill(AstraColor.surfaceElevated)
                    .frame(height: AstraSpacing.lg)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement()
        .accessibilityLabel(Text(String(localized: "Loading this piece", comment: "Accessibility label for the item detail loading state")))
    }
}

/// Spec §21 "Recoverable error" plus "Retry".
///
/// The retry button is gated on `AstraError.isRetryable` rather than always
/// shown: `.unimplemented` and `.validation` can never succeed on a second
/// attempt, and a button that cannot work is the dead button spec §22 bans.
private struct ClosetItemDetailErrorView: View {
    let error: AstraError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: AstraSpacing.md) {
            Image(systemName: iconName)
                .astraIcon(.display)
                .foregroundStyle(AstraColor.textMuted)
                .accessibilityHidden(true)

            Text(title)
                .astraText(.title2)
                .foregroundStyle(AstraColor.textPrimary)
                .multilineTextAlignment(.center)

            Text(error.message)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if error.isRetryable {
                Button(String(localized: "Try again", comment: "Retries loading the garment"), action: onRetry)
                    .buttonStyle(.astraSecondary)
                    .padding(.top, AstraSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AstraSpacing.xxl)
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch error.category {
        case .network: String(localized: "You're offline", comment: "Item detail error title")
        case .auth: String(localized: "Please sign in again", comment: "Item detail error title")
        case .rateLimited: String(localized: "One moment", comment: "Item detail error title")
        default: String(localized: "We couldn't open this piece", comment: "Item detail error title")
        }
    }

    private var iconName: String {
        switch error.category {
        case .network: "wifi.slash"
        case .auth: "lock"
        case .rateLimited: "hourglass"
        default: "exclamationmark.triangle"
        }
    }
}

// MARK: - Previews

#Preview("Loaded") {
    NavigationStack {
        ClosetItemDetailView(
            viewModel: ClosetItemDetailViewModel(
                itemID: SampleData.closetItems.first?.id ?? UUID(),
                closetRepository: MockClosetRepository(),
                imageURLResolver: MockClosetImageURLResolver()
            )
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Not found") {
    // `MockClosetRepository` throws for an id it has never seen, which is
    // the same failure a deleted row produces in production.
    NavigationStack {
        ClosetItemDetailView(
            viewModel: ClosetItemDetailViewModel(
                itemID: UUID(),
                closetRepository: MockClosetRepository(),
                imageURLResolver: MockClosetImageURLResolver()
            )
        )
    }
    .preferredColorScheme(.dark)
}
