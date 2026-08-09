//
//  OutfitDetailViewModel.swift
//  AstraStyle
//
//  Drives `OutfitDetailView` — spec §6.12 "Outfit detail": full-height
//  hero, name, occasion tags, weather range, item strip, why it works,
//  fit notes, color story, actions (Mark Worn, Schedule, Edit, Visualize,
//  Share), and the "Complete this look" missing-item CTA.
//
//  Patterned on `ClosetItemDetailViewModel` (`Features/Closet/ViewModels`)
//  rather than on `HomeViewModel`: this screen composes exactly two
//  repositories plus a units lookup for one record, not five repositories
//  fused into a dashboard, so it depends on `OutfitRepository` /
//  `ClosetRepository` / `ProfileRepository` directly rather than through a
//  `*Providing` fusion type — the same "compose only when the fan-out
//  earns it" call `HomeBriefProviding`'s own header makes.
//
//  READ THIS BEFORE ADDING A NEW SENTENCE TO THIS SCREEN.
//  `OutfitRecommendation.unmeasured` lists exactly which score inputs the
//  server fell back to a prior for, and is the one place in this app that
//  can answer "is a claim about why this outfit works actually earned?"
//  It does not reach here. `outfits.description` (`Outfit.description`,
//  what `saveOutfit` writes from `recommendation.reason`) is the only
//  copy this screen has for "why it works", and `outfits` has no column
//  for `unmeasured` — confirmed against
//  `supabase/migrations/20260728100400_outfits.sql`, which was written
//  before this field existed on `OutfitRecommendation` at all. So by the
//  time a saved outfit reaches this view model, whether its description
//  rests on a prior is not merely absent, it is UNKNOWABLE from here.
//
//  This view model does not pretend otherwise in either direction: it
//  passes `outfit.description` through unedited when the server sent one
//  (never inventing a replacement, never appending anything of its own),
//  and it never adds a second sentence characterizing why colours, fits,
//  or the whole look "work" — every other reason-shaped section on this
//  screen (`OutfitDetailCopy.colorStoryNames`/`.fitNotes`, below) is
//  built exclusively from each garment's own recorded fields, which are
//  observed facts about a piece of clothing, not judgments the
//  compatibility scorer formed about how pieces relate. Closing the actual
//  gap — persisting `unmeasured` on `outfits` and having `saveOutfit` keep
//  it — is a `Domain`/migration change with its own blast radius across
//  every other `P4-OUTFIT` ticket's shared files, and deliberately out of
//  scope here; this comment exists so the gap stays visible instead of
//  looking, from inside this file, like it was never noticed.
//

import Foundation
import Observation

@MainActor
@Observable
public final class OutfitDetailViewModel {

    /// Everything the detail screen draws: the outfit row, its item
    /// slots, the owned garments those slots resolve to, their signed
    /// photo URLs, and the display units the weather range renders in.
    public struct OutfitDetail: Equatable, Sendable {
        public var outfit: Outfit
        public var items: [OutfitItem]
        public var closetItemsByID: [UUID: ClosetItem]
        public var imageURLsByClosetItemID: [UUID: URL]
        public var units: UnitsPreference

        public init(
            outfit: Outfit,
            items: [OutfitItem],
            closetItemsByID: [UUID: ClosetItem],
            imageURLsByClosetItemID: [UUID: URL],
            units: UnitsPreference
        ) {
            self.outfit = outfit
            self.items = items
            self.closetItemsByID = closetItemsByID
            self.imageURLsByClosetItemID = imageURLsByClosetItemID
            self.units = units
        }

        public func closetItem(for item: OutfitItem) -> ClosetItem? {
            item.closetItemID.flatMap { closetItemsByID[$0] }
        }

        /// The owned garments behind `items`, in outfit (`sort_order`)
        /// order, dropping any slot that did not resolve to a closet item
        /// (a missing-item slot, or one whose `ClosetItem` could not be
        /// loaded). What `OutfitDetailCopy`'s fit/colour helpers read.
        public var ownedClosetItems: [ClosetItem] {
            items.compactMap(closetItem(for:))
        }
    }

    public enum ViewState: Equatable {
        case loading
        case loaded(OutfitDetail)
        case failed(AstraError)

        public var detail: OutfitDetail? {
            if case .loaded(let detail) = self { return detail }
            return nil
        }
    }

    public private(set) var state: ViewState = .loading

    /// Independent of `state`, matching every other detail screen in this
    /// app: a cached outfit still renders while offline (spec §7 "Cached
    /// closet and outfits remain viewable").
    public private(set) var isOffline = false

    public private(set) var isMarkingWorn = false

    /// The last action failure, held separately from `state` — a failed
    /// mark-worn does not invalidate an outfit that loaded correctly.
    public private(set) var actionError: AstraError?

    private let outfitID: UUID
    private let outfitRepository: OutfitRepository
    private let closetRepository: ClosetRepository
    private let closetImageURLResolver: ClosetImageURLResolving
    private let profileRepository: ProfileRepository
    private let analyticsClient: AnalyticsClient
    private let networkMonitor: NetworkReachabilityMonitoring

    public init(
        outfitID: UUID,
        outfitRepository: OutfitRepository,
        closetRepository: ClosetRepository,
        closetImageURLResolver: ClosetImageURLResolving,
        profileRepository: ProfileRepository,
        analyticsClient: AnalyticsClient = NoOpAnalyticsClient(),
        networkMonitor: NetworkReachabilityMonitoring = SystemNetworkReachabilityMonitor()
    ) {
        self.outfitID = outfitID
        self.outfitRepository = outfitRepository
        self.closetRepository = closetRepository
        self.closetImageURLResolver = closetImageURLResolver
        self.profileRepository = profileRepository
        self.analyticsClient = analyticsClient
        self.networkMonitor = networkMonitor
    }

    // MARK: - Loading

    public func onAppear() async {
        isOffline = await networkMonitor.isOffline()
        guard case .loading = state else { return }
        await load()
    }

    public func refresh() async {
        await load()
    }

    private func load() async {
        isOffline = await networkMonitor.isOffline()
        do {
            async let outfitTask = outfitRepository.fetchOutfit(id: outfitID)
            async let itemsTask = outfitRepository.fetchOutfitItems(outfitID: outfitID)
            async let unitsTask = resolveUnits()

            let outfit = try await outfitTask
            let items = try await itemsTask
            let units = await unitsTask

            let closetItemIDs = Set(items.compactMap(\.closetItemID))
            let closetItemsByID = await resolveClosetItems(ids: closetItemIDs)
            let imageURLs = await resolveImageURLs(for: Array(closetItemsByID.values))

            state = .loaded(OutfitDetail(
                outfit: outfit,
                items: items,
                closetItemsByID: closetItemsByID,
                imageURLsByClosetItemID: imageURLs,
                units: units
            ))
        } catch let error as AstraError {
            state = .failed(error)
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }

    /// Falls back to `.imperial` on a profile-read failure. The screen's
    /// job did not change when this fails — the outfit still loads — so a
    /// units lookup failing degrades the temperature FORMAT, not the
    /// screen.
    private func resolveUnits() async -> UnitsPreference {
        (try? await profileRepository.fetchCurrentProfile())?.units ?? .imperial
    }

    /// One `fetchItems()` read rather than N `fetchItem(id:)` calls — the
    /// same choice `DefaultHomeBriefProvider` makes for its closet-size
    /// check, for the same reason: an outfit's item strip is at most a
    /// handful of garments, and the whole closet is already the cheapest
    /// way to resolve them. A failed read degrades to an empty map rather
    /// than failing the screen — the outfit itself still loaded.
    private func resolveClosetItems(ids: Set<UUID>) async -> [UUID: ClosetItem] {
        guard !ids.isEmpty else { return [:] }
        let allItems = (try? await closetRepository.fetchItems()) ?? []
        return Dictionary(uniqueKeysWithValues: allItems.filter { ids.contains($0.id) }.map { ($0.id, $0) })
    }

    /// Signs one photo per garment — whichever `ClosetItemImage` is
    /// flagged primary, falling back to the first on file — in as few
    /// round trips as `ClosetImageURLResolving` allows: N `fetchImages`
    /// reads (one per garment; the protocol has no batch form of that
    /// call) followed by ONE signing request for all of them together.
    ///
    /// Failure anywhere in here degrades to "no photos" rather than to
    /// `.failed` — the same rule `ClosetItemDetailViewModel.resolveURLs`
    /// applies: a Storage hiccup says nothing about whether the outfit
    /// itself loaded correctly.
    private func resolveImageURLs(for closetItems: [ClosetItem]) async -> [UUID: URL] {
        guard !closetItems.isEmpty else { return [:] }
        var heroPathByItemID: [UUID: String] = [:]
        for item in closetItems {
            guard let images = try? await closetRepository.fetchImages(forItem: item.id),
                  let hero = images.first(where: { $0.isPrimary }) ?? images.first
            else { continue }
            heroPathByItemID[item.id] = hero.displayStoragePath
        }
        guard !heroPathByItemID.isEmpty else { return [:] }
        let resolvedByPath = (try? await closetImageURLResolver.resolve(storagePaths: Array(heroPathByItemID.values))) ?? [:]
        return heroPathByItemID.compactMapValues { resolvedByPath[$0] }
    }

    // MARK: - Actions (spec §6.12 "Actions")

    /// "Mark Worn". Mirrors `HomeViewModel.markPrimaryOutfitWorn`: an
    /// in-flight flag, no optimistic mutation of the outfit itself (there
    /// is nothing on `Outfit` for a wear to change — `wear_count` lives on
    /// each `closet_items` row via the server's trigger, not here), and a
    /// failure that clears to `actionError` rather than replacing the
    /// loaded screen.
    public func markWorn(at wornAt: Date = .now) async {
        guard !isMarkingWorn, let outfit = state.detail?.outfit else { return }
        isMarkingWorn = true
        defer { isMarkingWorn = false }
        actionError = nil
        do {
            try await outfitRepository.recordWear(
                outfitID: outfit.id,
                wornAt: wornAt,
                occasion: nil,
                rating: nil,
                feedback: nil
            )
            analyticsClient.log(.outfitMarkedWorn(outfitID: outfit.id))
        } catch let error as AstraError {
            actionError = error
            isOffline = await networkMonitor.isOffline()
        } catch {
            actionError = AstraError(category: .unknown, message: error.localizedDescription)
            isOffline = await networkMonitor.isOffline()
        }
    }

    public func clearActionError() {
        actionError = nil
    }
}

// MARK: - Presentation copy

/// What the outfit detail screen says about garments it did not form a
/// compatibility opinion about — every string here is read off a
/// `ClosetItem`'s own recorded fields, never off the compatibility
/// scorer. See `OutfitDetailViewModel`'s header and
/// `OutfitRecommendation.unmeasured`'s doc comment for the rule this
/// keeps: a garment's own colour is a fact (`ClosetItem.primaryColor`,
/// written when the piece was scanned or added, the same status as its
/// brand or size); a claim that two garments' colours WORK TOGETHER is a
/// scored judgment that can rest on a prior. This type only ever produces
/// the first kind.
public enum OutfitDetailCopy {

    /// Every colour word actually recorded across the outfit's owned
    /// garments, primary before secondary, in outfit order. Duplicates are
    /// kept (two navy pieces is information, not noise) and blanks are
    /// dropped rather than shown as an empty swatch.
    public static func colorStoryNames(for closetItems: [ClosetItem]) -> [String] {
        closetItems.flatMap { item -> [String] in
            var names: [String] = []
            if let primary = item.primaryColor, !primary.isEmpty {
                names.append(primary)
            }
            names.append(contentsOf: item.secondaryColors.filter { !$0.isEmpty })
            return names
        }
    }

    /// One garment and the fit recorded for it — spec §6.6's fit
    /// vocabulary, the same one the closet's own item detail screen
    /// reads, never a judgment this screen forms about how the pieces sit
    /// together.
    public struct FitNote: Identifiable, Hashable, Sendable {
        public var id: UUID { itemID }
        public let itemID: UUID
        public let itemName: String
        public let fit: ItemFit

        public init(itemID: UUID, itemName: String, fit: ItemFit) {
            self.itemID = itemID
            self.itemName = itemName
            self.fit = fit
        }
    }

    /// One entry per garment that has a recorded fit; garments with none
    /// are omitted rather than shown with a blank fit, matching
    /// `ClosetItemDetailView`'s "absent field is omitted, not dashed"
    /// convention.
    public static func fitNotes(for closetItems: [ClosetItem]) -> [FitNote] {
        closetItems.compactMap { item in
            guard let fit = item.fit else { return nil }
            return FitNote(itemID: item.id, itemName: item.name, fit: fit)
        }
    }

    /// "Client meeting · Smart casual".
    ///
    /// This used to be documented as mirroring Home's hero card, so the same
    /// tags read the same way on both screens. That card is gone — Home is
    /// one look now and names no occasions — which leaves this the only
    /// occasion line in the app rather than one of two that had to agree.
    public static func occasionLine(_ occasionTags: [String]) -> String? {
        guard !occasionTags.isEmpty else { return nil }
        return occasionTags.joined(separator: " · ").capitalized
    }

    /// Share-sheet text. `outfit.description` is appended only when the
    /// server actually sent one — never padded out with a sentence this
    /// screen invented itself, the same "absent is honest" rule applied to
    /// the one piece of freeform text this screen hands to something
    /// outside the app.
    public static func shareText(for outfit: Outfit) -> String {
        guard let description = outfit.description, !description.isEmpty else {
            return outfit.name
        }
        return "\(outfit.name)\n\n\(description)"
    }
}
