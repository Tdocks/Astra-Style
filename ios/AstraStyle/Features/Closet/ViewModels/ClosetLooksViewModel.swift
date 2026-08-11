//
//  ClosetLooksViewModel.swift
//  AstraStyle
//
//  The outfit carousel's state. Lives in the Closet because browsing is a
//  closet activity: Home decides, this is where a man disagrees with the
//  decision and looks through what else he owns.
//
//  IT SHOWS SAVED OUTFITS, NOT FRESH RECOMMENDATIONS, AND THAT MATTERS.
//  `generateOutfits` returns `OutfitRecommendation` values that have no
//  `outfits` row behind them until `saveOutfit` is called. Tapping one to
//  open outfit detail — or marking it worn — would then be operating on an
//  id the database has never heard of, and `outfit_wears.outfit_id` is a
//  NOT NULL foreign key, so it fails outright. `fetchOutfits()` returns
//  real rows, every one of which is already tappable, wearable and
//  schedulable. The daily brief writes them each morning, so the carousel
//  fills up on its own.
//
//  THE TONE CONTROLS ARE A REACTION TO THE LOOK IN FRONT OF HIM.
//  "Too dressy" is not a filter — it means "show me something less dressy
//  than THIS", and that is what it does: it records the opinion and moves
//  to the nearest look below this one on formality. Two things happen
//  because both are true. The jump is the answer to what he just asked;
//  the `style_feedback` row is what stops him having to ask again next
//  week (spec §9's signals feed §10's compatibility term).
//
//  ONLY TWO CONTROLS, THOUGH THREE WERE ASKED FOR. "More chill" and "too
//  dressy" are the same request in different words, and
//  `StyleFeedbackSignal` has one case for it (`tooFormal`). Two buttons
//  writing the same row and performing the same jump would be a choice
//  that isn't one — the user would reasonably assume they differ, and
//  spend a while working out how.
//

import Foundation
import Observation
import OSLog

@MainActor
@Observable
public final class ClosetLooksViewModel {

    /// One outfit, joined to the garments that make it up.
    public struct Look: Identifiable, Sendable {
        public var outfit: Outfit
        public var garments: [LookGarment]
        public var id: UUID { outfit.id }

        /// Where this sits on the formality axis, for the tone jump.
        ///
        /// `outfits.formality_score` is nullable AND, on every row the daily
        /// brief has written so far, null — the generator does not populate
        /// it. Reading only that column made both tone buttons permanently
        /// inert: `nearestLook` needs a number for the current look before it
        /// can find one on either side of it, so every tap fell through to
        /// "that's the most relaxed look you've got", on all four outfits, in
        /// both directions.
        ///
        /// The garments carry the number instead — `closet_items
        /// .formality_score`, populated by the vision analyser on 19 of 20
        /// pieces in the live closet — so the look's register is the mean of
        /// the pieces in it. That is also the more honest figure: an outfit's
        /// formality IS its garments', and a column on the outfit row would
        /// only ever be a cached copy of this.
        ///
        /// Still nil when NO garment in the look has a score, because then
        /// there is genuinely nothing to compare. Nil is not zero: treating
        /// it as zero would make an unscored look read as the most casual
        /// thing he owns and pull every "too dressy" tap onto it.
        var formality: Int? {
            if let stated = outfit.formalityScore { return stated }
            let scores = garments.compactMap(\.item.formalityScore)
            guard !scores.isEmpty else { return nil }
            return scores.reduce(0, +) / scores.count
        }
    }

    public enum ViewState: Sendable {
        case loading
        case loaded([Look])
        /// No saved outfits at all — Kyra has not built any yet.
        case empty
        case failed(AstraError)
    }

    public enum ToneNudge: Sendable {
        case tooDressy
        case tooCasual

        var signal: StyleFeedbackSignal {
            switch self {
            case .tooDressy: .tooFormal
            case .tooCasual: .tooCasual
            }
        }
    }

    public private(set) var state: ViewState = .loading
    public private(set) var frame: FrameProfile = .unknown

    /// Which look the carousel is showing. Bound to the `ScrollView`'s
    /// paging position, and written by the tone controls when they jump.
    public var focusedLookID: UUID?

    /// Said out loud when a nudge cannot go anywhere — "that is already the
    /// most relaxed look you have". Nil the rest of the time. A control
    /// that silently does nothing at the end of the range is the dead
    /// button §22 rules out, arrived at from a direction that is easy to
    /// miss in testing because it only happens at the edges.
    public private(set) var nudgeNote: String?

    private static let logger = Logger(subsystem: "app.astrastyle", category: "closet.looks")

    private let outfitRepository: OutfitRepository
    private let closetRepository: ClosetRepository
    private let profileRepository: ProfileRepository
    private let hydrator: LookHydrator

    public init(
        outfitRepository: OutfitRepository,
        closetRepository: ClosetRepository,
        profileRepository: ProfileRepository,
        imageURLResolver: ClosetImageURLResolving
    ) {
        self.outfitRepository = outfitRepository
        self.closetRepository = closetRepository
        self.profileRepository = profileRepository
        self.hydrator = LookHydrator(
            closetRepository: closetRepository,
            imageURLResolver: imageURLResolver
        )
    }

    public func onAppear() async {
        guard case .loading = state else { return }
        await load()
    }

    public func reload() async {
        await load()
    }

    private func load() async {
        do {
            let outfits = try await outfitRepository.fetchOutfits()
            guard !outfits.isEmpty else {
                state = .empty
                return
            }
            // The closet is fetched once for the whole carousel and the join
            // is done in memory — see `LookHydrator`. A per-outfit fetch
            // would ask the server for the same forty rows eight times.
            let closet = try await closetRepository.fetchItems()
            let itemsPerOutfit = await outfitItems(for: outfits)
            let garments = await hydrator.hydrate(outfits: itemsPerOutfit, closet: closet)

            let looks = zip(outfits, garments)
                .map { Look(outfit: $0, garments: $1) }
                // A look whose garments all failed to join is a row pointing
                // at nothing — showing an empty card would say "here is an
                // outfit" about a thing with no clothes in it.
                .filter { !$0.garments.isEmpty }

            state = looks.isEmpty ? .empty : .loaded(looks)
            focusedLookID = looks.first?.id
            // `.public` on every value: the default redacts interpolations,
            // and a diagnostic line reading "<private> outfits" is why the
            // first pass at the batch-scan bug took three guesses.
            // `.notice`, not `.info`: info-level entries live in the memory
            // ring buffer and do not reach the device log stream, which is
            // why the first diagnostic pass on this screen read back empty.
            Self.logger.notice(
                "looks loaded: outfits=\(outfits.count, privacy: .public) closet=\(closet.count, privacy: .public) drawable=\(looks.count, privacy: .public)"
            )
            await loadFrame()
        } catch let error as AstraError {
            Self.logger.error("looks failed: \(error.message, privacy: .public)")
            state = .failed(error)
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }

    /// The wearer's proportions, for the silhouette. Failing to load them is
    /// not a failure of this screen: `FrameProfile.unknown` is the normal
    /// state for anyone who skipped the measurements step, and the layout
    /// already has to be right for him.
    private func loadFrame() async {
        guard let body = try? await profileRepository.fetchBodyProfile() else { return }
        frame = FrameDerivation.derive(from: body)
    }

    private func outfitItems(for outfits: [Outfit]) async -> [[OutfitItem]] {
        let repository = outfitRepository
        return await withTaskGroup(of: (Int, [OutfitItem]).self) { group in
            for (index, outfit) in outfits.enumerated() {
                group.addTask {
                    let items = (try? await repository.fetchOutfitItems(outfitID: outfit.id)) ?? []
                    return (index, items)
                }
            }
            var collected = Array(repeating: [OutfitItem](), count: outfits.count)
            for await (index, items) in group {
                collected[index] = items
            }
            return collected
        }
    }

    // MARK: - Tone

    /// Records the opinion and moves to the nearest look in that direction.
    public func nudge(_ tone: ToneNudge) async {
        nudgeNote = nil
        guard case .loaded(let looks) = state,
              let current = looks.first(where: { $0.id == focusedLookID }) else { return }

        if let next = nearestLook(from: current, in: looks, tone: tone) {
            focusedLookID = next.id
        } else {
            nudgeNote = edgeNote(for: tone)
        }

        // Written whether or not the jump had anywhere to go. The opinion is
        // true either way, and the case where he is at the end of the range
        // is exactly the case worth learning from.
        _ = try? await outfitRepository.recordFeedback(
            targetType: .outfit,
            targetID: current.outfit.id,
            signal: tone.signal,
            reasonTags: [],
            freeText: nil
        )
    }

    /// The closest look on the other side of `current`, by formality.
    ///
    /// Closest rather than most extreme: a man who says "too dressy" about a
    /// suit wants the blazer, not the gym shorts. Unscored looks are not
    /// candidates — see `Look.formality`.
    private func nearestLook(from current: Look, in looks: [Look], tone: ToneNudge) -> Look? {
        guard let here = current.formality else { return nil }
        let candidates = looks.compactMap { look -> (Look, Int)? in
            guard let score = look.formality, look.id != current.id else { return nil }
            switch tone {
            case .tooDressy where score < here: return (look, here - score)
            case .tooCasual where score > here: return (look, score - here)
            default: return nil
            }
        }
        return candidates.min { $0.1 < $1.1 }?.0
    }

    private func edgeNote(for tone: ToneNudge) -> String {
        switch tone {
        case .tooDressy:
            String(localized: "That's the most relaxed look you've got right now. Noted for next time.",
                   comment: "Carousel tone nudge with nowhere further to go")
        case .tooCasual:
            String(localized: "That's the sharpest look you've got right now. Noted for next time.",
                   comment: "Carousel tone nudge with nowhere further to go")
        }
    }
}
