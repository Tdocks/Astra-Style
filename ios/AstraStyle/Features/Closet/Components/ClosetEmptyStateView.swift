//
//  ClosetEmptyStateView.swift
//  AstraStyle
//
//  The Closet tab's non-garment states: the three empty states, the
//  recoverable-error state, the offline banner, and the loading skeleton.
//
//  FOUR TYPES IN ONE FILE, ON PURPOSE. They are one concern — what the
//  closet shows when it is not showing clothes — and all four are used by
//  both `ClosetView` and `ClosetCategoryView`. Splitting them into four
//  files would leave four two-screen components with nothing to say to
//  each other; keeping them together is what makes it obvious at a glance
//  that all four exist and that none of them is missing.
//
//  WHY NOT REUSE `HomeEmptyStateView`. It carries Home's framing —
//  "Let's build your first look", about today's outfit — and the closet's
//  first screen is about the wardrobe, not about today. Reaching into
//  another feature's `Components/` directory would also couple Closet to
//  Home's internals for the sake of one shared sentence. That sentence is
//  spec §21's fixed copy and is duplicated here verbatim and deliberately;
//  the moment a third screen needs this shape, the shape (not the copy)
//  belongs in `Core/DesignSystem`, promoted the way `AstraRemoteImage` and
//  `AstraTextField` already were.
//
//  FOUR EMPTY STATES, NOT ONE. An empty closet, a category with nothing
//  in it, a search that found nothing, and a filter set that excludes
//  everything are four different facts about a wardrobe and want four
//  different sentences and four different actions. Collapsing them into
//  one "Nothing here yet" would tell a man with forty shirts that his
//  closet is empty because he mistyped a brand.
//
//  TWO OF THE FOUR CARRY A SECOND, MANUAL WAY IN — AND THE OTHER TWO MUST
//  NOT. An empty closet and an empty category are both the same fact ("you
//  own nothing here"), and both used to offer only "Scan", which reaches
//  a scanner that has not shipped. A screen that says "Add five pieces and
//  Kyra can begin building real outfits" and then offers no way to add a
//  piece is spec §22's dead end in its purest form, so both get "Add one
//  by hand" underneath — the path that works today, at secondary weight
//  because scanning is the one the spec leads with and the one that will
//  be faster the moment it exists.
//
//  "Nothing matches that" does NOT get it. That closet is full; the man is
//  looking at a query, not at an absence. Offering him a garment form
//  there would answer a mistyped brand name with "buy something else",
//  and the action that fixes his actual problem — Clear Search — would be
//  competing with it for the eye.
//
//  THE FILTER STATE IS THE SAME ARGUMENT, ARRIVED AT FROM THE SAME PLACE,
//  AND IT IS MORE CLEARLY RIGHT THERE THAN IN THE SEARCH CASE. A man who
//  has narrowed to navy outerwear in fair condition has told the app, in
//  eight facets' worth of detail, exactly which garments he owns that he
//  wants to see. Answering that with a form for a garment he does NOT own
//  is not just off-topic, it misreads what he said. His closet is full and
//  he is looking at a scope, not at an absence — so this state gets no
//  manual add either, and its recovery is the one that puts his own
//  garments back: turning the filters off.
//
//  IT NEEDS ITS OWN CLOSURE RATHER THAN REUSING `onClearSearch`, because
//  the two clear two different things and neither should silently do the
//  other's job. A man who cleared his filters and found his query gone
//  too would have no way to tell which change put the garments back —
//  `ClosetViewModel.clearFilters()` records the same reasoning from the
//  other side.
//

import SwiftUI

struct ClosetEmptyStateView: View {
    let reason: ClosetViewModel.EmptyReason
    let onScan: () -> Void
    let onAddManually: () -> Void
    let onClearSearch: () -> Void
    let onClearFilters: () -> Void

    var body: some View {
        VStack(spacing: AstraSpacing.md) {
            Spacer(minLength: AstraSpacing.xl)

            Image(systemName: symbolName)
                .astraIcon(.display)
                .foregroundStyle(AstraColor.accentChampagne)
                .accessibilityHidden(true)

            Text(title)
                .astraText(.title2)
                .foregroundStyle(AstraColor.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AstraSpacing.xl)

            AstraButton(title: actionTitle, action: action)
                .padding(.top, AstraSpacing.sm)

            if showsManualAdd {
                Button(manualAddTitle, action: onAddManually)
                    .buttonStyle(.astraSecondary)
                    .accessibilityHint(Text(manualAddHint))
                    .accessibilityIdentifier("closet.empty.addManually")
            }

            Spacer(minLength: AstraSpacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(AstraSpacing.pagePadding)
        .accessibilityElement(children: .contain)
    }

    /// See this file's header: the two "you own nothing here" states, and
    /// neither of the two where the closet is full and it is the
    /// narrowing that is wrong.
    private var showsManualAdd: Bool {
        switch reason {
        case .closetIsEmpty, .categoryIsEmpty: true
        case .noSearchMatches, .noFilterMatches: false
        }
    }

    private var manualAddTitle: String {
        String(localized: "Add One by Hand", comment: "Opens the manual garment form from a closet empty state")
    }

    private var manualAddHint: String {
        String(localized: "Type in a piece without using the camera", comment: "VoiceOver hint for the manual add button")
    }

    /// Each state's glyph names the control that produced it, so the
    /// picture and the button underneath are about the same thing: a
    /// magnifier for a query, and the header's own filter glyph — the
    /// same `line.3.horizontal.decrease` `ClosetFilterButton` draws — for
    /// a filter set.
    private var symbolName: String {
        switch reason {
        case .closetIsEmpty, .categoryIsEmpty: "hanger"
        case .noSearchMatches: "magnifyingglass"
        case .noFilterMatches: "line.3.horizontal.decrease"
        }
    }

    private var title: String {
        switch reason {
        case .closetIsEmpty:
            String(localized: "Your closet is empty", comment: "Closet overview empty state title")
        case .categoryIsEmpty(let category):
            String(localized: "No \(category.displayName) yet", comment: "Closet category empty state title, e.g. 'No Outerwear yet'")
        case .noSearchMatches:
            String(localized: "Nothing matches that", comment: "Closet search empty state title")
        case .noFilterMatches:
            // Deliberately not "Nothing matches that" again. Two states
            // reachable from the same screen, sharing one sentence, would
            // leave the user unable to tell which of his two narrowings
            // emptied the grid.
            String(localized: "No pieces fit those filters", comment: "Closet filter empty state title")
        }
    }

    /// The first case is spec §21's copy, verbatim and not to be reworded.
    private var message: String {
        switch reason {
        case .closetIsEmpty:
            String(localized: "Add five pieces and Kyra can begin building real outfits.", comment: "Closet overview empty state, fixed by the master spec")
        case .categoryIsEmpty:
            // "Add", not "Scan": there are two ways in below this
            // sentence now, and naming only one of them makes the other
            // look like it does something else.
            String(localized: "Nothing in this part of your closet yet. Add a piece and it will show up here.", comment: "Closet category empty state")
        case .noSearchMatches(let query):
            String(localized: "Nothing in your closet matches “\(query)”. Try a brand, a colour, or part of a name.", comment: "Closet search found no items")
        case .noFilterMatches:
            // Names the reason a set of individually-populated filters can
            // still return nothing — every facet was offered because some
            // garment carries it, but no ONE garment carries all of them.
            // Without that sentence the panel looks broken rather than
            // strict. The second half points at the cheaper fix first:
            // reopening the panel undoes one facet, where the button
            // below undoes all of them.
            String(localized: "You own pieces in each of those, but none in all of them at once. Drop a filter, or clear them all.", comment: "Closet filters excluded every item")
        }
    }

    private var actionTitle: String {
        switch reason {
        case .closetIsEmpty:
            String(localized: "Scan Your First Item", comment: "Closet empty state call to action")
        case .categoryIsEmpty:
            String(localized: "Scan an Item", comment: "Closet category empty state call to action")
        case .noSearchMatches:
            String(localized: "Clear Search", comment: "Clears the closet search field")
        case .noFilterMatches:
            String(localized: "Clear Filters", comment: "Turns every closet filter off")
        }
    }

    private var action: () -> Void {
        switch reason {
        case .closetIsEmpty, .categoryIsEmpty:
            return onScan
        case .noSearchMatches:
            return onClearSearch
        case .noFilterMatches:
            return onClearFilters
        }
    }
}

// MARK: - Error

/// Spec §21 "Recoverable error" + "Retry", applied to the closet.
///
/// The retry button is conditional on `AstraError.isRetryable`, which is
/// the whole reason that property exists. A missing capability or an
/// expired session cannot be fixed by tapping Try Again, and offering the
/// button anyway would be a control that does nothing — precisely what
/// spec §22's acceptance bar rules out, error states included.
struct ClosetErrorStateView: View {
    let error: AstraError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: AstraSpacing.md) {
            Spacer(minLength: AstraSpacing.xl)

            Image(systemName: symbolName)
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
                .padding(.horizontal, AstraSpacing.xl)

            if error.isRetryable {
                Button(action: onRetry) {
                    Text(String(localized: "Try Again", comment: "Retries loading the closet"))
                }
                .buttonStyle(.astraSecondary)
                .padding(.horizontal, AstraSpacing.xxl)
                .padding(.top, AstraSpacing.sm)
            }

            Spacer(minLength: AstraSpacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(AstraSpacing.pagePadding)
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch error.category {
        case .network: String(localized: "You're offline", comment: "Closet failed to load because the device is offline")
        case .auth: String(localized: "Please sign in again", comment: "Closet failed to load because the session expired")
        case .rateLimited: String(localized: "One moment", comment: "Closet failed to load because of rate limiting")
        case .unimplemented: String(localized: "Not ready yet", comment: "Closet capability that has not shipped")
        default: String(localized: "Couldn't open your closet", comment: "Generic closet load failure")
        }
    }

    private var symbolName: String {
        switch error.category {
        case .network: "wifi.slash"
        case .auth: "lock"
        case .rateLimited: "hourglass"
        case .unimplemented: "hammer"
        default: "exclamationmark.triangle"
        }
    }
}

// MARK: - Offline

/// Shown over otherwise-normal cached content (spec §7: "Cached closet and
/// outfits remain viewable"). Offline is not, by itself, an error.
struct ClosetOfflineBanner: View {
    var body: some View {
        HStack(spacing: AstraSpacing.xs) {
            Image(systemName: "wifi.slash")
                .accessibilityHidden(true)
            Text(Self.message)
                .astraText(.caption)
        }
        .foregroundStyle(AstraColor.textSecondary)
        .padding(.horizontal, AstraSpacing.sm)
        .padding(.vertical, AstraSpacing.xxs)
        .frame(maxWidth: .infinity)
        .background(AstraColor.surfaceElevated, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(Self.message))
    }

    private static var message: String {
        String(localized: "You're offline. Showing your saved closet.", comment: "Offline banner above cached closet content")
    }
}

// MARK: - Loading

/// Spec §21 "Skeleton state" for the closet.
///
/// Built from the real tile geometry — an aspect ratio and token-sized
/// text bars — rather than from measured pixel heights, so the skeleton
/// keeps matching the grid it stands in for when either changes.
struct ClosetLoadingSkeletonView: View {
    let columnCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.lg) {
            // Half-width title bar, then a full-width search bar — the
            // header's own shape, so the skeleton does not jump when the
            // real header replaces it.
            HStack(spacing: 0) {
                bar(height: AstraSpacing.xl)
                Color.clear.frame(height: AstraSpacing.xl)
            }
            bar(height: AstraSize.minTapTarget)

            LazyVGrid(columns: columns, spacing: AstraSpacing.md) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                        .fill(AstraColor.surfaceElevated)
                        .aspectRatio(ClosetGridMetrics.tileAspectRatio, contentMode: .fit)
                }
            }
        }
        .padding(AstraSpacing.pagePadding)
        .redacted(reason: .placeholder)
        // One announcement, not a dozen redacted rectangles.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Loading your closet", comment: "VoiceOver label for the closet loading state")))
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: AstraSpacing.md), count: columnCount)
    }

    private func bar(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: AstraRadius.small, style: .continuous)
            .fill(AstraColor.surfaceElevated)
            .frame(height: height)
            .frame(maxWidth: .infinity)
    }
}
