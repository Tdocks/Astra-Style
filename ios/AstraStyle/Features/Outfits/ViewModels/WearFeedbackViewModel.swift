//
//  WearFeedbackViewModel.swift
//  AstraStyle
//
//  P4-OUTFIT-14: the "Mark Worn" flow's write path. A shared, reusable
//  view model — not owned by any one screen — because both the Outfit
//  builder (this ticket's own reachable entry point, wired for an outfit
//  it is currently editing) and Outfit detail / the Daily Brief hero card
//  (P4-OUTFIT-11, P4-HOME-03 — different tickets, not yet built) need the
//  identical write behind "Wore it" / "Skip" / "Dislike", the same way
//  `P4-OUTFIT-13`'s alternative-looks carousel is one component reused by
//  two screens rather than duplicated per screen.
//
//  REQUIRES A REAL, SAVED OUTFIT. `outfitID` is not optional — an
//  in-progress builder canvas that has never been saved has no
//  `outfit_items` rows for `bump_closet_item_wear_stats()` to join
//  against (see `LiveOutfitRepository.saveOutfit`'s own header), so
//  `recordWear` against it would either fail a foreign-key check or,
//  worse, succeed while silently bumping nothing. The caller is
//  responsible for only presenting these controls once a real id exists —
//  `OutfitBuilderView` gates on `backingOutfitID`.
//
//  EXACTLY-ONE-ROW, BY CONSTRUCTION, NOT BY A GUARD HERE. The client-minted
//  `OutfitWear.id`/`StyleFeedback.id` and `LiveOutfitRepository`'s
//  offline-queue-on-failure behaviour already guarantee at-most-once
//  delivery for a given tap (see that type's header). What THIS file adds
//  on top is at-most-once PER TAP: `isRecordingWear`/`isRecordingFeedback`
//  refuse a second call while the first is still in flight, so a double
//  tap on "Wore it" cannot mint two separate `OutfitWear` rows before the
//  first request even returns.
//

import Foundation
import Observation

@MainActor
@Observable
public final class WearFeedbackViewModel {

    public enum Outcome: Equatable {
        case wore
        case feedback(StyleFeedbackSignal)
    }

    public let outfitID: UUID

    public private(set) var isRecordingWear = false
    public private(set) var isRecordingFeedback = false
    public private(set) var lastOutcome: Outcome?
    public private(set) var actionError: AstraError?

    private let outfitRepository: OutfitRepository
    private let analyticsClient: AnalyticsClient

    public init(outfitID: UUID, outfitRepository: OutfitRepository, analyticsClient: AnalyticsClient = NoOpAnalyticsClient()) {
        self.outfitID = outfitID
        self.outfitRepository = outfitRepository
        self.analyticsClient = analyticsClient
    }

    /// "Wore it": writes the one `outfit_wears` row spec §6.12/§9 call for.
    /// `wear_count` on every constituent `closet_items` row is bumped by
    /// `bump_closet_item_wear_stats()` server-side (the trigger on
    /// `outfit_wears` insert, `20260728101200_functions_and_triggers.sql`)
    /// — this method's job ends at getting exactly one row inserted.
    ///
    /// `weather_snapshot` is left at its database default (`{}`):
    /// `OutfitRepository.recordWear`'s existing signature has no parameter
    /// for it, and this ticket uses that method as given rather than
    /// widening a signature several other call sites and tests already
    /// depend on. See this app's outfit builder delivery notes.
    public func markWorn(occasion: String? = nil, rating: Int? = nil, feedback: String? = nil, at wornAt: Date = .now) async {
        guard !isRecordingWear else { return }
        isRecordingWear = true
        defer { isRecordingWear = false }
        actionError = nil
        do {
            try await outfitRepository.recordWear(outfitID: outfitID, wornAt: wornAt, occasion: occasion, rating: rating, feedback: feedback)
            lastOutcome = .wore
            analyticsClient.log(.outfitMarkedWorn(outfitID: outfitID))
            AstraHaptics.success()
        } catch let error as AstraError {
            actionError = error
        } catch {
            actionError = AstraError(category: .unknown, message: error.localizedDescription)
        }
    }

    /// "Skip" or "Dislike": writes one `style_feedback` row against this
    /// outfit with the given signal. Both actions share this path — they
    /// differ only in which `StyleFeedbackSignal` is passed — because
    /// neither writes to `outfit_wears` at all; that is exactly what
    /// distinguishes a rejection from a wear (this file's own header).
    public func recordFeedback(_ signal: StyleFeedbackSignal, reasonTags: [String] = []) async {
        guard !isRecordingFeedback else { return }
        isRecordingFeedback = true
        defer { isRecordingFeedback = false }
        actionError = nil
        do {
            try await outfitRepository.recordFeedback(
                targetType: .outfit,
                targetID: outfitID,
                signal: signal,
                reasonTags: reasonTags,
                freeText: nil
            )
            lastOutcome = .feedback(signal)
            analyticsClient.log(.outfitRejected(outfitID: outfitID, reasonTags: reasonTags.isEmpty ? [signal.rawValue] : reasonTags))
            AstraHaptics.selection()
        } catch let error as AstraError {
            actionError = error
        } catch {
            actionError = AstraError(category: .unknown, message: error.localizedDescription)
        }
    }

    public func skip() async {
        await recordFeedback(.skipped)
    }

    public func dislike() async {
        await recordFeedback(.dislike)
    }

    public func clearActionError() {
        actionError = nil
    }
}
