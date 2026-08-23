//
//  OutfitDetailView.swift
//  AstraStyle
//
//  Spec §6.12 "Outfit detail": full-height hero, outfit name, occasion
//  tags, weather range, item strip, why it works, fit notes, color story,
//  actions (Mark Worn, Schedule, Edit, Visualize, Share), and the
//  "Complete this look" missing-item CTA — in that order, matching the
//  spec's own list.
//
//  No network call happens in this file; everything routes through
//  `OutfitDetailViewModel`, per CLAUDE.md's "no network calls in views"
//  rule extended to the view-model boundary.
//
//  EVERY ACTION IS REAL (spec §22 "No dead buttons"). Mark Worn writes a
//  real `outfit_wears` row. Schedule and Edit open real, already-reachable
//  modal flows (`AppModalRoute.addOccasion` / `.outfitBuilder`) — both
//  currently resolve to `FeaturePlaceholderView`, same as every other
//  not-yet-built destination in this app, but the navigation itself is
//  real and states plainly that the screen behind it isn't finished yet.
//  Visualize is the one spec's own ticket calls out by name: it opens the
//  Studio flow entry point, "stubbed until Phase 6, but the navigation
//  hook exists" (`P4-OUTFIT-11`'s acceptance criteria). Share hands a real
//  string to the system share sheet.
//
//  NO ALTERNATIVES CAROUSEL HERE, AND THERE IS NO LONGER ONE TO ADD.
//  `AlternativeLooksCarouselView` was `P4-OUTFIT-13`'s shared component,
//  written to be reused by the Daily Brief and this screen. This screen
//  never took it: "alternatives" is a property of a BRIEF (today's primary
//  outfit and its siblings), not of an `Outfit` row, and this screen is
//  reached from a bare `outfitID: UUID` with no brief in scope — the
//  nearest substitute would be an arbitrary sample of the user's other
//  saved outfits presented as curated alternatives to this one, which they
//  are not.
//
//  Then Home became one look and dropped its alternatives module, which
//  took the component's only real consumer with it, so the file is gone.
//  Browsing other outfits now happens in the Closet's looks carousel,
//  which is scoped to what it actually shows: every saved outfit, said to
//  be exactly that. If a brief-scoped alternatives strip is ever wanted
//  here, the honest version of it is a new component with the brief
//  threaded through the route — not this one restored.
//

import SwiftUI

public struct OutfitDetailView: View {
    @State private var viewModel: OutfitDetailViewModel
    @Environment(AppRouter.self) private var router

    public init(viewModel: OutfitDetailViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.xl) {
                if viewModel.isOffline, viewModel.state.detail != nil {
                    OutfitDetailOfflineBanner()
                }
                content
            }
            .padding(.horizontal, AstraSpacing.pagePadding)
            .padding(.vertical, AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .refreshable { await viewModel.refresh() }
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
        .alert(
            Text(actionFailureTitle),
            isPresented: actionErrorPresented,
            presenting: viewModel.actionError
        ) { _ in
            Button(dismissTitle) { viewModel.clearActionError() }
        } message: { error in
            Text(error.message)
        }
        .onChange(of: viewModel.pendingPaywall) { _, context in
            if let context {
                router.presentModal(.paywall(context: context))
                viewModel.clearPendingPaywall()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            OutfitDetailSkeleton()

        case .failed(let error):
            OutfitDetailErrorView(error: error) {
                Task { await viewModel.refresh() }
            }

        case .loaded(let detail):
            OutfitDetailContent(
                detail: detail,
                isMarkingWorn: viewModel.isMarkingWorn,
                isUpdatingVisibility: viewModel.isUpdatingVisibility,
                isOwned: viewModel.isOwnedByCurrentUser,
                hasReported: viewModel.hasReportedLookbook,
                onMarkWorn: markWorn,
                onSchedule: { router.presentModal(.addOccasion) },
                onEdit: { router.presentModal(.outfitBuilder(.builder(startingOutfitID: detail.outfit.id))) },
                onVisualize: { router.presentModal(.studioGeneration(outfitID: detail.outfit.id)) },
                onTogglePublic: {
                    Task {
                        let next: OutfitVisibility = detail.outfit.visibility == .shared ? .personal : .shared
                        await viewModel.setVisibility(next)
                    }
                },
                onReport: { Task { await viewModel.reportLookbook() } },
                showsStudioActions: viewModel.isOwnedByCurrentUser,
                onCompleteLook: { candidateID in
                    router.push(HomeRoute.productDecision(candidateID: candidateID))
                }
            )
        }
    }

    /// Haptics live here, not in the view model, so a unit test of
    /// `markWorn()` never reaches for the Taptic Engine, and so the
    /// "success" feedback fires on the OUTCOME rather than on the tap —
    /// same rule `ClosetItemDetailView.markWorn()` follows.
    private func markWorn() {
        Task {
            await viewModel.markWorn()
            if viewModel.actionError == nil {
                AstraHaptics.success()
            }
        }
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
        String(localized: "That didn't save", comment: "Title of the alert shown when an outfit detail action fails")
    }

    private var dismissTitle: String {
        String(localized: "OK", comment: "Dismisses an alert")
    }
}

// MARK: - Loaded content

private struct OutfitDetailContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let detail: OutfitDetailViewModel.OutfitDetail
    let isMarkingWorn: Bool
    let isUpdatingVisibility: Bool
    let isOwned: Bool
    let hasReported: Bool
    let onMarkWorn: () -> Void
    let onSchedule: () -> Void
    let onEdit: () -> Void
    let onVisualize: () -> Void
    let onTogglePublic: () -> Void
    let onReport: () -> Void
    /// Wave E: Visualize is still the generate door from this screen.
    /// (ADR 0015); hiding this control too would leave no way to see the look.
    let showsStudioActions: Bool
    let onCompleteLook: (UUID) -> Void

    private var outfit: Outfit { detail.outfit }

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xl) {
            OutfitDetailHeroSection(outfit: outfit)

            header

            if !detail.items.isEmpty {
                OutfitItemStripSection(detail: detail, onCompleteLook: onCompleteLook)
            }

            whyItWorksSection

            fitNotesSection

            colorStorySection

            actionRow
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            HStack(alignment: .top) {
                Text(outfit.name)
                    .astraText(.title1)
                    .foregroundStyle(AstraColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: AstraSpacing.sm)
                if let score = outfit.compatibilityScore {
                    AstraScoreMeter(score: score, title: compatibilityTitle, style: .compact)
                }
            }

            if let occasionLine = OutfitDetailCopy.occasionLine(outfit.occasionTags) {
                Text(occasionLine)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
            }

            if let weatherLine {
                Text(weatherLine)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.successOlive)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// "Why it works" (spec §6.12). Present only when the server actually
    /// sent a reason — see `OutfitDetailViewModel`'s header for why this
    /// is the one honest option available to this screen: `outfits` has
    /// no column recording which inputs behind that sentence were
    /// measured versus a prior, so the description is shown exactly as
    /// received, never edited, never supplemented with a second claim of
    /// this screen's own.
    @ViewBuilder
    private var whyItWorksSection: some View {
        if let description = outfit.description, !description.isEmpty {
            VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                AstraSectionHeader(title: whyItWorksTitle)
                Text(description)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "Fit notes" (spec §6.12): each owned garment's own recorded fit —
    /// never a claim about how the pieces fit together, which nothing on
    /// this screen has measured. See `OutfitDetailCopy`'s header.
    @ViewBuilder
    private var fitNotesSection: some View {
        let notes = OutfitDetailCopy.fitNotes(for: detail.ownedClosetItems)
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                AstraSectionHeader(title: fitNotesTitle)
                ForEach(notes) { note in
                    HStack(spacing: AstraSpacing.xxs) {
                        Text(note.itemName)
                            .astraText(.body)
                            .foregroundStyle(AstraColor.textPrimary)
                        Text("·")
                            .foregroundStyle(AstraColor.textMuted)
                        Text(note.fit.displayName)
                            .astraText(.body)
                            .foregroundStyle(AstraColor.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// "Color story" (spec §6.12): every colour word actually recorded
    /// across the outfit's owned garments — reuses `ClosetColorSwatchRow`,
    /// the same swatch treatment the closet item detail screen uses for
    /// the identical data shape, rather than a second implementation.
    @ViewBuilder
    private var colorStorySection: some View {
        let names = OutfitDetailCopy.colorStoryNames(for: detail.ownedClosetItems)
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                AstraSectionHeader(title: colorStoryTitle)
                ClosetColorSwatchRow(label: colorStoryFieldLabel, colorNames: names)
            }
        }
    }

    /// Spec §6.12's five actions. Stacked at accessibility Dynamic Type
    /// sizes for the same reason `ClosetItemActionRow.secondaryActions`
    /// stacks: two `maxWidth: .infinity` buttons sharing a row at AX5
    /// leaves too little width for either label to read.
    private var actionRow: some View {
        VStack(spacing: AstraSpacing.sm) {
            if isOwned {
                ownedActions
            } else {
                foreignActions
            }
        }
    }

    private var ownedActions: some View {
        VStack(spacing: AstraSpacing.sm) {
            AstraButton(title: markWornTitle, isLoading: isMarkingWorn, action: onMarkWorn)
                .accessibilityIdentifier("outfitDetail.action.markWorn")

            actionsGroup(
                first: ActionSpec(title: scheduleTitle, identifier: "outfitDetail.action.schedule", action: onSchedule),
                second: ActionSpec(title: editTitle, identifier: "outfitDetail.action.edit", action: onEdit)
            )
            if showsStudioActions {
                actionsGroup(
                    first: ActionSpec(title: visualizeTitle, identifier: "outfitDetail.action.visualize", action: onVisualize),
                    second: nil
                )
            }

            Button(action: onTogglePublic) {
                Text(publicToggleTitle)
                    .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
            }
            .buttonStyle(.astraSecondary)
            .disabled(isUpdatingVisibility)
            .accessibilityIdentifier("outfitDetail.action.visibility")

            ShareLink(item: OutfitDetailCopy.shareText(for: outfit)) {
                Label(shareTitle, systemImage: "square.and.arrow.up")
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.accentChampagneAccessible)
                    .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
            }
            .accessibilityIdentifier("outfitDetail.action.share")
        }
    }

    private var foreignActions: some View {
        VStack(spacing: AstraSpacing.sm) {
            ShareLink(item: OutfitDetailCopy.shareText(for: outfit)) {
                Label(shareTitle, systemImage: "square.and.arrow.up")
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.accentChampagneAccessible)
                    .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
            }
            .accessibilityIdentifier("outfitDetail.action.share")

            Button(action: onReport) {
                Text(hasReported ? reportedTitle : reportTitle)
                    .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
            }
            .buttonStyle(.astraSecondary)
            .disabled(hasReported)
            .accessibilityIdentifier("outfitDetail.action.report")
        }
    }

    /// One secondary action's title, accessibility identifier, and handler.
    /// A named type rather than a tuple: SwiftLint's `large_tuple` rule
    /// caps tuples at two members, and a `(title:identifier:action:)`
    /// triple is exactly the shape `actionsGroup`/`secondaryButton` need.
    private struct ActionSpec {
        let title: String
        let identifier: String
        let action: () -> Void
    }

    @ViewBuilder
    private func actionsGroup(first: ActionSpec, second: ActionSpec?) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: AstraSpacing.sm) {
                secondaryButton(first)
                if let second { secondaryButton(second) }
            }
        } else {
            HStack(spacing: AstraSpacing.sm) {
                secondaryButton(first)
                if let second { secondaryButton(second) }
            }
        }
    }

    private func secondaryButton(_ spec: ActionSpec) -> some View {
        Button(spec.title, action: spec.action)
            .buttonStyle(.astraSecondary)
            .accessibilityIdentifier(spec.identifier)
    }

    private var weatherLine: String? {
        guard let min = outfit.weatherMin, let max = outfit.weatherMax else { return nil }
        let range = AstraWeatherFormatting.temperatureRange(low: min, high: max, units: detail.units)
        return String(localized: "Suited for \(range)", comment: "Outfit detail weather range line")
    }

    private var compatibilityTitle: String {
        String(localized: "Compatibility", comment: "Outfit detail score meter title")
    }

    private var whyItWorksTitle: String {
        String(localized: "Why It Works", comment: "Outfit detail section header")
    }

    private var fitNotesTitle: String {
        String(localized: "Fit Notes", comment: "Outfit detail section header")
    }

    private var colorStoryTitle: String {
        String(localized: "Color Story", comment: "Outfit detail section header")
    }

    private var colorStoryFieldLabel: String {
        String(localized: "Colors", comment: "Label above the outfit's colour swatches")
    }

    private var markWornTitle: String {
        String(localized: "Mark Worn", comment: "Records that the user wore this outfit today")
    }

    private var scheduleTitle: String {
        String(localized: "Schedule", comment: "Opens the flow to schedule this outfit for an occasion")
    }

    private var editTitle: String {
        String(localized: "Edit", comment: "Opens this outfit in the builder")
    }

    private var visualizeTitle: String {
        String(localized: "Visualize", comment: "Opens Style Studio to preview this outfit on the user")
    }

    private var shareTitle: String {
        String(localized: "Share", comment: "Opens the system share sheet for this outfit")
    }

    private var publicToggleTitle: String {
        outfit.visibility == .shared
            ? String(localized: "Make this look private", comment: "Removes a look from Discover")
            : String(localized: "Show this look to other men", comment: "Opts a worn look into Discover")
    }

    private var reportTitle: String {
        String(localized: "Report this look", comment: "Stub report of a public lookbook")
    }

    private var reportedTitle: String {
        String(localized: "Reported", comment: "Lookbook report already sent")
    }
}

// MARK: - Hero

private struct OutfitDetailHeroSection: View {
    let outfit: Outfit

    var body: some View {
        AstraRemoteImage(
            url: outfit.heroImageURL ?? outfit.generatedPreviewURL,
            aspectRatio: 4.0 / 5.0,
            accessibilityDescription: heroDescription
        )
        .overlay(alignment: .bottomLeading) {
            // §11/§13's generated-image labelling, and now the only place
            // in the app that applies it: a curated `heroImageURL` never
            // carries the badge; a Style-Studio-only `generatedPreviewURL`
            // always does.
            if outfit.heroImageURL == nil, outfit.generatedPreviewURL != nil {
                GeneratedImageBadge()
                    .padding(AstraSpacing.sm)
            }
        }
    }

    private var heroDescription: String {
        String(localized: "Editorial preview of \(outfit.name)", comment: "Accessibility description of the outfit detail hero image")
    }
}

// MARK: - Item strip

/// Spec §6.12 "Item strip" and its "Missing item CTA: 'Complete this
/// look.'" — the two are the same horizontal row, a garment tile for
/// every resolved slot and a "Complete this look" tile for every
/// unresolved one, rather than two separate sections competing for the
/// same real estate.
private struct OutfitItemStripSection: View {
    let detail: OutfitDetailViewModel.OutfitDetail
    let onCompleteLook: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(title: title)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AstraSpacing.sm) {
                    ForEach(detail.items) { item in
                        if let closetItem = detail.closetItem(for: item) {
                            OutfitItemStripTile(item: closetItem, imageURL: detail.imageURLsByClosetItemID[closetItem.id])
                        } else if item.isMissingItem, let candidateID = item.productCandidateID {
                            CompleteThisLookTile(role: item.role) { onCompleteLook(candidateID) }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var title: String {
        String(localized: "The Look", comment: "Outfit detail item strip section header")
    }
}

private struct OutfitItemStripTile: View {
    // 20 × the 4 pt base unit, matching `ClosetItemHeroSection
    // .stripThumbnailSize`'s own reasoning: no dedicated token exists yet
    // for this exact square.
    private static let tileSize = AstraSpacing.unit * 20

    let item: ClosetItem
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            AstraRemoteImage(
                url: imageURL,
                aspectRatio: 1,
                thumbnail: .outfitItemStripTile,
                cornerRadius: AstraRadius.small,
                accessibilityDescription: item.name
            )
            .frame(width: Self.tileSize, height: Self.tileSize)

            Text(item.name)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textPrimary)
                .lineLimit(1)
        }
        .frame(width: Self.tileSize, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(item.name))
    }
}

/// Spec §6.12's "Missing item CTA". A real, tappable control — not a
/// disabled placeholder — that opens the product decision page for the
/// unowned slot (spec §6.18's "shop the look" flow).
private struct CompleteThisLookTile: View {
    private static let tileSize = AstraSpacing.unit * 20

    let role: OutfitItemRole
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                RoundedRectangle(cornerRadius: AstraRadius.small, style: .continuous)
                    .strokeBorder(AstraColor.divider, style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .frame(width: Self.tileSize, height: Self.tileSize)
                    .overlay {
                        Image(systemName: "plus")
                            .astraIcon(.control)
                            .foregroundStyle(AstraColor.accentChampagneAccessible)
                    }

                Text(title)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.accentChampagneAccessible)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: Self.tileSize, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(hint))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("outfitDetail.completeLook.\(role.rawValue)")
    }

    private var title: String {
        String(localized: "Complete this look", comment: "CTA for a missing garment slot in an outfit")
    }

    private var hint: String {
        String(localized: "Opens where to buy this piece", comment: "Accessibility hint on the Complete this look CTA")
    }
}

// MARK: - Non-content states

private struct OutfitDetailOfflineBanner: View {
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
        String(localized: "You're offline. Showing the last saved copy of this outfit.", comment: "Offline banner on the outfit detail screen")
    }
}

private struct OutfitDetailSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                .fill(AstraColor.surfaceElevated)
                .aspectRatio(4.0 / 5.0, contentMode: .fit)

            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: AstraRadius.small, style: .continuous)
                    .fill(AstraColor.surfaceElevated)
                    .frame(height: AstraSpacing.lg)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement()
        .accessibilityLabel(Text(String(localized: "Loading this outfit", comment: "Accessibility label for the outfit detail loading state")))
    }
}

private struct OutfitDetailErrorView: View {
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
                Button(String(localized: "Try again", comment: "Retries loading the outfit"), action: onRetry)
                    .buttonStyle(.astraSecondary)
                    .padding(.top, AstraSpacing.xs)
                    .accessibilityIdentifier("outfitDetail.action.retry")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AstraSpacing.xxl)
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch error.category {
        case .network: String(localized: "You're offline", comment: "Outfit detail error title")
        case .auth: String(localized: "Please sign in again", comment: "Outfit detail error title")
        case .rateLimited: String(localized: "One moment", comment: "Outfit detail error title")
        default: String(localized: "We couldn't open this outfit", comment: "Outfit detail error title")
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
        OutfitDetailView(
            viewModel: OutfitDetailViewModel(
                outfitID: SampleData.heroOutfit.id,
                outfitRepository: MockOutfitRepository(),
                closetRepository: MockClosetRepository(),
                closetImageURLResolver: MockClosetImageURLResolver(),
                profileRepository: MockProfileRepository()
            )
        )
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}

#Preview("Not found") {
    NavigationStack {
        OutfitDetailView(
            viewModel: OutfitDetailViewModel(
                outfitID: UUID(),
                outfitRepository: MockOutfitRepository(),
                closetRepository: MockClosetRepository(),
                closetImageURLResolver: MockClosetImageURLResolver(),
                profileRepository: MockProfileRepository()
            )
        )
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}
