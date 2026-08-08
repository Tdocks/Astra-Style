//
//  OutfitBuilderViewModel.swift
//  AstraStyle
//
//  Drives the Outfit builder (spec §6.13, P4-OUTFIT-12). Patterned on
//  `ClosetViewModel`/`HomeViewModel`: an explicit load state, protocol-only
//  dependencies, per-action in-flight booleans, and zero networking above
//  this file.
//
//  TWO ENTRY MODES, ONE VIEW MODEL. `startingOutfitID == nil` is "Create
//  outfit" (`AppRouter.startCreateOutfit()`): every rail slot starts empty
//  and the canvas is built up by tapping. `startingOutfitID != nil` loads
//  an already-saved `Outfit` (reached from wherever P4-OUTFIT-11/P4-HOME-03
//  eventually link "Edit") and hydrates the rail from its `outfit_items`.
//
//  WHY "SAVE" ALWAYS INSERTS A NEW OUTFIT, EVEN WHEN EDITING ONE. There is
//  no repository method that rewrites an existing outfit's `outfit_items`
//  set — `updateOutfit(_:)` only ever touches the `outfits` row's own
//  columns (name/description/etc.), and `saveOutfit(from:name:closetItems:)`
//  is a plain `INSERT`, not an upsert (see `LiveOutfitRepository.saveOutfit`'s
//  own header). Re-using `saveOutfit` for an edit-in-progress with the
//  ORIGINAL outfit id would collide with that existing row's primary key.
//  So `save()` always mints a fresh id and inserts a new `outfits` row —
//  "Save as outfit" is taken at its word. A true in-place edit (replace
//  `outfit_items` on the same id) is a real gap this ticket does not close;
//  see this type's `save()` doc.
//
//  THE LIVE COMPATIBILITY METER'S HONESTY GATE LIVES HERE, NOT IN THE
//  SCORER. `LocalCompatibilityScorer` will happily score one garment
//  against nothing — `currentCompatibility` is what refuses to ask it to,
//  below two filled slots, because a single garment has no partner to be
//  "compatible" WITH and a confident number there would be exactly the
//  confounded reading spec forbids.

import Foundation
import Observation

@MainActor
@Observable
public final class OutfitBuilderViewModel {

    // MARK: - State

    public enum LoadState: Equatable {
        case loading
        case loaded
        case failed(AstraError)
    }

    /// "Ask Kyra to finish" (spec §6.13) is wired to a stub until
    /// `P5-KYRA-06` ships the real `create_outfit` tool call. `.comingSoon`
    /// is the honest state spec §22 requires instead of a silent no-op —
    /// see `askKyraToFinish()`.
    public enum AskKyraState: Equatable {
        case idle
        case comingSoon
    }

    public private(set) var loadState: LoadState = .loading
    public private(set) var slots: [OutfitBuilderSlot]
    public private(set) var closetItems: [ClosetItem] = []
    /// The real `outfits.id` this canvas is backed by, once one exists —
    /// either loaded from `startingOutfitID` or minted by a successful
    /// `save()`. `nil` means nothing has been persisted yet, which is what
    /// gates the wear-feedback controls (`WearFeedbackViewModel` needs a
    /// real, saved outfit with real `outfit_items` rows — see that type's
    /// header).
    public private(set) var backingOutfitID: UUID?
    public var outfitName: String = ""
    public private(set) var isRegenerating = false
    public private(set) var isSaving = false
    public private(set) var savedOutfit: Outfit?
    public private(set) var actionError: AstraError?
    public private(set) var askKyraState: AskKyraState = .idle

    // MARK: - Dependencies

    private let outfitRepository: OutfitRepository
    private let closetRepository: ClosetRepository
    private let compatibilityScorer: CompatibilityScoring
    private let startingOutfitID: UUID?

    /// Forwarding-only: this class logs nothing itself. Spec §18's event
    /// list names `outfit_generated` (the generation endpoint,
    /// `P4-OUTFIT-07`) and `outfit_marked_worn`/`outfit_rejected`
    /// (`WearFeedbackViewModel`, which this screen hosts but does not
    /// own) — there is no "outfit builder opened" or "outfit saved" event
    /// in that list, and inventing one here would put a name on the wire
    /// the spec does not define (`ClosetViewModel`'s own header states
    /// this same rule for the closet screen). It is held only so
    /// `makeWearFeedbackViewModel()` can hand it to the child view model
    /// that DOES own real events, the same way
    /// `ClosetViewModel.makeAddItemViewModel()` forwards its own
    /// `analyticsClient` to the form it builds.
    private let analyticsClient: AnalyticsClient

    public init(
        outfitRepository: OutfitRepository,
        closetRepository: ClosetRepository,
        compatibilityScorer: CompatibilityScoring = LocalCompatibilityScorer(),
        analyticsClient: AnalyticsClient = NoOpAnalyticsClient(),
        startingOutfitID: UUID? = nil
    ) {
        self.outfitRepository = outfitRepository
        self.closetRepository = closetRepository
        self.compatibilityScorer = compatibilityScorer
        self.analyticsClient = analyticsClient
        self.startingOutfitID = startingOutfitID
        self.slots = ClothingCategory.outfitBuilderRailOrder.map { OutfitBuilderSlot(category: $0) }
        self.backingOutfitID = startingOutfitID
    }

    // MARK: - Lifecycle

    public func onAppear() async {
        guard case .loading = loadState else { return }
        await load()
    }

    public func retry() async {
        await load()
    }

    private func load() async {
        loadState = .loading
        do {
            let items = try await closetRepository.fetchItems()
            closetItems = items

            if let startingOutfitID {
                let outfit = try await outfitRepository.fetchOutfit(id: startingOutfitID)
                let outfitItems = try await outfitRepository.fetchOutfitItems(outfitID: startingOutfitID)
                outfitName = outfit.name
                hydrateSlots(from: outfitItems, closetItems: items)
            }
            loadState = .loaded
        } catch let error as AstraError {
            loadState = .failed(error)
        } catch {
            loadState = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }

    /// Places each `outfit_items` row's owned garment into the rail slot
    /// matching its role. A row this build cannot place — a missing-item
    /// slot with no `closetItemID`, a role with no rail counterpart, or a
    /// referenced garment that no longer resolves against the loaded
    /// closet — is skipped rather than guessed at; the slot simply stays
    /// empty, which is the honest reading of "this piece isn't here".
    private func hydrateSlots(from outfitItems: [OutfitItem], closetItems: [ClosetItem]) {
        let itemsByID = Dictionary(uniqueKeysWithValues: closetItems.map { ($0.id, $0) })
        for outfitItem in outfitItems {
            guard
                let closetItemID = outfitItem.closetItemID,
                let closetItem = itemsByID[closetItemID],
                let category = ClothingCategory(rawValue: outfitItem.role.rawValue),
                let index = slots.firstIndex(where: { $0.category == category })
            else { continue }
            slots[index].item = closetItem
        }
    }

    // MARK: - Slot editing (tap-to-replace / long-press-to-lock)

    /// The closet items a "tap to replace" picker for `category` should
    /// offer — every owned garment of that category, whether or not it is
    /// currently wearable. Availability is shown, never used to hide an
    /// option: a man who wants to plan an outfit around a jacket that is
    /// at the tailor should still be able to put it on the canvas.
    public func availableItems(for category: ClothingCategory) -> [ClosetItem] {
        closetItems.filter { $0.category == category }
    }

    /// Tap-to-replace. A no-op on a locked slot — locking is what "tap to
    /// replace" is locked OUT of, per spec §6.13's own pairing of the two
    /// gestures.
    public func selectItem(_ item: ClosetItem, for category: ClothingCategory) {
        guard let index = slots.firstIndex(where: { $0.category == category }), !slots[index].isLocked else { return }
        slots[index].item = item
        AstraHaptics.selection()
    }

    public func clearItem(for category: ClothingCategory) {
        guard let index = slots.firstIndex(where: { $0.category == category }), !slots[index].isLocked else { return }
        slots[index].item = nil
    }

    /// Long-press-to-lock. Refuses to lock an empty slot — there is
    /// nothing there for "regenerate" to preserve, so a lock on it would
    /// be a control with no effect (spec §22).
    public func toggleLock(for category: ClothingCategory) {
        guard let index = slots.firstIndex(where: { $0.category == category }), slots[index].item != nil else { return }
        slots[index].isLocked.toggle()
        AstraHaptics.selection()
    }

    // MARK: - Live compatibility meter

    public var filledItems: [ClosetItem] { slots.compactMap(\.item) }

    /// `nil` below two filled slots — see this file's header. Recomputed
    /// on every read, which is what makes this "live": nothing caches it,
    /// so a tap that swaps one slot is reflected the instant the view
    /// re-reads this property.
    public var currentCompatibility: CompatibilityBreakdown? {
        guard filledItems.count >= 2 else { return nil }
        return compatibilityScorer.scoreOutfit(items: filledItems, context: CompatibilityContext())
    }

}

// The remaining behaviour (regenerate, Ask Kyra, save) is split into its
// own extension purely to keep this type under SwiftLint's
// `type_body_length` ceiling — the same reason `LiveOutfitRepository`
// splits into `+Offline.swift`/`+Brief.swift`, done here as an in-file
// extension instead of a second file since none of it shares a natural
// seam (client, cache, etc.) the way that repository's split does.
extension OutfitBuilderViewModel {

    // MARK: - Regenerate (lock + regenerate unlocked slots, P4-OUTFIT-08)

    /// Re-ranks and applies the top result to every UNLOCKED slot only.
    ///
    /// THE INVARIANT IS ENFORCED HERE, NOT TRUSTED FROM THE SERVER.
    /// `applyToUnlockedSlots(_:)` below never writes to a locked slot's
    /// `item`, no matter what `rankOutfits` returns — that is the
    /// acceptance criterion ("locking an item and regenerating changes
    /// only unlocked slots") as a client-side guarantee, testable without
    /// depending on the ranking endpoint's own correctness.
    public func regenerate() async {
        guard !isRegenerating else { return }
        isRegenerating = true
        defer { isRegenerating = false }
        actionError = nil
        do {
            let lockedItemIDs = slots.compactMap { $0.isLocked ? $0.item?.id : nil }
            let candidateOutfitIDs = backingOutfitID.map { [$0] } ?? []
            let recommendations = try await outfitRepository.rankOutfits(
                candidateOutfitIDs: candidateOutfitIDs,
                lockedClosetItemIDs: lockedItemIDs
            )
            guard let top = recommendations.first else { return }
            applyToUnlockedSlots(top)
        } catch let error as AstraError {
            actionError = error
        } catch {
            actionError = AstraError(category: .unknown, message: error.localizedDescription)
        }
    }

    /// Overwrites only unlocked slots, one garment per rail category from
    /// `recommendation.itemIDs`, never reusing a garment already placed in
    /// a locked slot. A category the recommendation has nothing for is
    /// left exactly as it was — this never clears a slot on a guess.
    ///
    /// Internal (not `private`) so `Tests/UnitTests/OutfitBuilderViewModelTests.swift`
    /// can exercise the merge invariant directly against a hand-built
    /// `OutfitRecommendation`, without depending on what a stub
    /// `OutfitRepository.rankOutfits` happens to return.
    func applyToUnlockedSlots(_ recommendation: OutfitRecommendation) {
        let itemsByID = Dictionary(uniqueKeysWithValues: closetItems.map { ($0.id, $0) })
        let recommendedByCategory = Dictionary(grouping: recommendation.itemIDs.compactMap { itemsByID[$0] }, by: \.category)
        var usedItemIDs = Set(slots.compactMap { $0.isLocked ? $0.item?.id : nil })

        for index in slots.indices where !slots[index].isLocked {
            let category = slots[index].category
            guard let candidate = recommendedByCategory[category]?.first(where: { !usedItemIDs.contains($0.id) }) else { continue }
            slots[index].item = candidate
            usedItemIDs.insert(candidate.id)
        }
    }

    // MARK: - Ask Kyra to finish (stub until P5-KYRA-06)

    /// Spec §6.13's "Ask Kyra to finish" action, before the real
    /// `create_outfit` tool call exists. This is a real, reachable state
    /// change — the view renders `.comingSoon` as an honest "arrives with
    /// Kyra" message — not a silently absorbed tap (spec §22).
    public func askKyraToFinish() {
        askKyraState = .comingSoon
    }

    public func dismissAskKyraState() {
        askKyraState = .idle
    }

    // MARK: - Save

    /// Persists the canvas as a new, real `outfits` row (see this file's
    /// header for why this never updates `startingOutfitID` in place).
    /// Requires at least one filled slot — an entirely empty canvas has
    /// nothing to save, and `AstraButton`'s disabled state on the view
    /// side keeps that from ever reaching here as a live tap in the first
    /// place; the guard is the same rule stated a second time, for callers
    /// other than the button.
    public func save() async {
        guard !isSaving, !filledItems.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        actionError = nil
        do {
            let trimmedName = outfitName.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmedName.isEmpty ? Self.defaultOutfitName : trimmedName
            let recommendation = OutfitRecommendation(
                id: UUID(),
                name: name,
                reason: "",
                compatibilityScore: currentCompatibility?.score() ?? 0,
                itemIDs: filledItems.map(\.id),
                missingProductIDs: []
            )
            let saved = try await outfitRepository.saveOutfit(from: recommendation, name: name, closetItems: closetItems)
            savedOutfit = saved
            backingOutfitID = saved.id
            AstraHaptics.success()
        } catch let error as AstraError {
            actionError = error
        } catch {
            actionError = AstraError(category: .unknown, message: error.localizedDescription)
        }
    }

    public func clearActionError() {
        actionError = nil
    }

    // MARK: - Wear feedback (P4-OUTFIT-14)

    /// Builds the "Mark Worn" flow's view model for the outfit this canvas
    /// is currently backed by, or `nil` before one exists.
    ///
    /// `nil` below `backingOutfitID` rather than an `OutfitBuilderView`
    /// that constructs `WearFeedbackViewModel` itself is deliberate: that
    /// type REQUIRES a real outfit id (see its own header), so the one
    /// place allowed to decide "a real one exists now" is this view
    /// model, not the view rendering it. `OutfitBuilderView` shows the
    /// wear-feedback controls exactly when this returns non-nil.
    public func makeWearFeedbackViewModel() -> WearFeedbackViewModel? {
        guard let backingOutfitID else { return nil }
        return WearFeedbackViewModel(
            outfitID: backingOutfitID,
            outfitRepository: outfitRepository,
            analyticsClient: analyticsClient
        )
    }

    static let defaultOutfitName = String(localized: "Untitled Look", comment: "Default name for an outfit saved from the builder with no name entered")
}
