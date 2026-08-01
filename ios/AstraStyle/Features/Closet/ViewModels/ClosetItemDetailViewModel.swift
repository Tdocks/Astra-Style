//
//  ClosetItemDetailViewModel.swift
//  AstraStyle
//
//  Drives `ClosetItemDetailView` — spec §6.15 "Item detail" (the field
//  list) and §6.15 "Actions" (mark worn, add to laundry, edit, archive).
//
//  Patterned on `Features/Home/ViewModels/HomeViewModel.swift`, the
//  reference implementation for this phase: an explicit `ViewState`
//  covering loading / loaded / empty / failed, an `isOffline` flag that is
//  ORTHOGONAL to that state, one in-flight boolean per action guarded with
//  `guard !flag` plus `defer`, and protocol-only dependencies so all of
//  them can be stubbed in a unit test.
//
//  TWO FIELDS §6.15 ASKS FOR THAT THIS SCREEN CANNOT SHOW.
//  * Care instructions. There is no property on `ClosetItem` and no column
//    on `closet_items` for it. Adding a `CodingKeys` entry here would fail
//    `scripts/check_column_drift.py` and would decode to nothing at
//    runtime. It needs a migration; it is not a UI omission, and nothing
//    on this screen pretends otherwise by rendering an empty "Care" row.
//  * Outfit count. Needs `outfit_items`, which is Phase 4. Rendering
//    "0 outfits" today would be a measured-looking zero for a table that
//    does not exist, which is worse than silence.
//
//  WEAR DATA IS REAL, JUST NOT YET FED FROM EVERYWHERE. `wear_count` and
//  `last_worn_at` are real columns and this screen reads and writes them
//  for real. Nothing writes them from `outfit_wears` yet (Phase 4), so
//  today they move only when a man taps Mark worn here. That is the
//  ticket's own "initially zero/empty", not a stub.
//
//  NO HAPTICS IN THIS FILE, DELIBERATELY. `AstraHaptics` wraps a UIKit
//  feedback generator; firing it from the view model would make every unit
//  test of `markWorn()` reach for device hardware, and would fire a
//  "saved" haptic in contexts with no screen at all. The view owns the
//  feedback, keyed on this type's published outcome.
//

import Foundation
import Observation

@MainActor
@Observable
public final class ClosetItemDetailViewModel {

    /// Everything the detail screen draws: the row, its photographs, and
    /// the signed URLs those photographs resolve to.
    public struct ItemDetail: Equatable, Sendable {
        public var item: ClosetItem
        /// Every image for the item, in the order they were fetched.
        public var images: [ClosetItemImage]
        /// `displayStoragePath` → signed URL. A path that could not be
        /// signed is ABSENT rather than mapped to a placeholder, matching
        /// `ClosetImageURLResolving`'s batch contract.
        public var imageURLs: [String: URL]

        public init(item: ClosetItem, images: [ClosetItemImage], imageURLs: [String: URL]) {
            self.item = item
            self.images = images
            self.imageURLs = imageURLs
        }

        /// §6.15 lists "Normalized cutout image" and "User photos" as two
        /// separate fields, so the hero prefers an image that actually HAS
        /// a background-removed cutout over one merely flagged primary — a
        /// raw capture blown up to hero size is the thing the cutout
        /// pipeline exists to avoid.
        public var heroImage: ClosetItemImage? {
            images.first(where: { $0.backgroundRemovedPath != nil })
                ?? images.first(where: { $0.isPrimary })
                ?? images.first
        }

        /// The remaining captures, shown as a strip beneath the hero.
        public var userPhotos: [ClosetItemImage] {
            guard let heroImage else { return [] }
            return images.filter { $0.id != heroImage.id }
        }

        public func url(for image: ClosetItemImage) -> URL? {
            imageURLs[image.displayStoragePath]
        }
    }

    public enum ViewState: Equatable {
        case loading
        case loaded(ItemDetail)
        /// The item exists and every field renders, but it has no
        /// photographs on file. Called out separately from `.loaded`
        /// because a 4:5 grey rectangle where the garment should be reads
        /// as a failed download; the empty case says so in words instead.
        case empty(ItemDetail)
        case failed(AstraError)

        /// Hand-written, and deliberately STRICTER than `HomeViewModel`'s.
        /// Home compares brief identity because a brief is replaced
        /// wholesale; this screen's entire job is field values changing
        /// under a stable `id`, so an identity-only `==` would report
        /// "unchanged" immediately after a mark-worn.
        public static func == (lhs: ViewState, rhs: ViewState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading):
                true
            case (.loaded(let left), .loaded(let right)), (.empty(let left), .empty(let right)):
                left == right
            case (.failed(let left), .failed(let right)):
                left == right
            default:
                false
            }
        }

        /// The detail behind `.loaded` or `.empty`. Actions operate on
        /// both: a garment with no photographs is still a garment you can
        /// wear, wash and archive.
        public var detail: ItemDetail? {
            switch self {
            case .loaded(let detail), .empty(let detail): detail
            case .loading, .failed: nil
            }
        }
    }

    public private(set) var state: ViewState = .loading

    /// Independent of `state`, exactly as on Home: a cached item still
    /// renders while offline (spec §7 "Cached closet and outfits remain
    /// viewable"), and edits queue rather than fail.
    public private(set) var isOffline = false

    // One flag per action rather than a single `isBusy`. Mark worn and
    // Add to laundry are adjacent buttons a man will tap in quick
    // succession; a shared flag would grey out the one he is reaching for.
    public private(set) var isMarkingWorn = false
    public private(set) var isUpdatingLaundryState = false
    public private(set) var isArchiving = false

    /// Set once `archiveItem` has succeeded. The screen watches this and
    /// leaves — see `archive()` for why this is a flag rather than a state.
    public private(set) var didArchive = false

    /// The last action failure, held separately from `state`.
    ///
    /// A failed mark-worn does not invalidate the item — replacing the
    /// whole screen with an error page would throw away content that is
    /// still correct. Same call the reference `HomeViewModel` makes for
    /// `markPrimaryOutfitWorn`, one level louder because these actions
    /// mutate and their rollback has to be visible.
    public private(set) var actionError: AstraError?

    private let itemID: UUID
    private let imageURLResolver: ClosetImageURLResolving
    private let networkMonitor: NetworkReachabilityMonitoring

    /// Public only so `ClosetItemDetailView` can hand it to
    /// `ClosetItemFormViewModel.editing(item:closetRepository:)` when the
    /// user taps Edit. The editor is a separate feature that owns its own
    /// writes; re-plumbing every one of them through this view model's API
    /// would be a worse seam than exposing the dependency it was given.
    public let closetRepository: ClosetRepository

    /// - Parameters:
    ///   - itemID: The `closet_items` row to show.
    ///   - closetRepository: Reads the item and performs all four actions.
    ///   - imageURLResolver: Signs storage paths (spec §15 — the
    ///     `user-content` bucket is private, so a path is not a URL).
    ///   - networkMonitor: Defaulted so callers that do not care about
    ///     offline reporting need not know it exists.
    ///
    /// There is deliberately no `analyticsClient`. `AnalyticsEvent` has no
    /// case for wearing a single garment — `outfitMarkedWorn(outfitID:)`
    /// is about an outfit — and logging a garment wear under an outfit
    /// event would put a number in a dashboard that means something else.
    /// Adding the case belongs with whoever owns `AnalyticsEvent.swift`.
    public init(
        itemID: UUID,
        closetRepository: ClosetRepository,
        imageURLResolver: ClosetImageURLResolving,
        networkMonitor: NetworkReachabilityMonitoring = SystemNetworkReachabilityMonitor()
    ) {
        self.itemID = itemID
        self.closetRepository = closetRepository
        self.imageURLResolver = imageURLResolver
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
            let item = try await closetRepository.fetchItem(id: itemID)
            let images = try await closetRepository.fetchImages(forItem: itemID)
            apply(ItemDetail(item: item, images: images, imageURLs: await resolveURLs(for: images)))
        } catch let error as AstraError {
            state = .failed(error)
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }

    /// Signing failures degrade the photographs, never the screen.
    ///
    /// One batch call, not one per image, per `ClosetImageURLResolving`'s
    /// own note about round trips. If the whole batch throws — expired
    /// session, Storage down — every field on this screen is still correct
    /// and still worth showing, so the failure resolves to "no photos"
    /// rather than to `.failed`. `AstraRemoteImage` renders a `nil` URL as
    /// its no-photo state, which is the truthful result.
    private func resolveURLs(for images: [ClosetItemImage]) async -> [String: URL] {
        guard !images.isEmpty else { return [:] }
        do {
            return try await imageURLResolver.resolve(storagePaths: images.map(\.displayStoragePath))
        } catch {
            return [:]
        }
    }

    /// The single place `.loaded` vs `.empty` is decided, so no action can
    /// accidentally promote a photo-less item into `.loaded`.
    private func apply(_ detail: ItemDetail) {
        state = detail.images.isEmpty ? .empty(detail) : .loaded(detail)
    }

    // MARK: - Actions (spec §6.15 "Actions")

    /// Increments `wear_count` by one and stamps `last_worn_at`.
    ///
    /// Optimistic, then reconciled with the row the repository returns.
    /// The optimistic step is not decoration: the counter is an inch from
    /// his thumb and a round trip of latency before it moves reads as a
    /// tap that missed. The reconcile step matters as much — the
    /// repository also moves `laundry_state` to `worn_once`, which this
    /// client must not try to predict.
    public func markWorn(at wornAt: Date = .now) async {
        guard !isMarkingWorn, let detail = state.detail else { return }
        isMarkingWorn = true
        defer { isMarkingWorn = false }
        actionError = nil

        var optimistic = detail
        optimistic.item.wearCount += 1
        optimistic.item.lastWornAt = wornAt
        apply(optimistic)

        do {
            var settled = detail
            settled.item = try await closetRepository.markWorn(id: itemID, wornAt: wornAt)
            apply(settled)
        } catch {
            await fail(error, rollingBackTo: detail)
        }
    }

    /// Sets `laundry_state`. Used both by the action row's one-tap
    /// "Into the wash" and by the laundry field's full picker.
    public func setLaundryState(_ newState: LaundryState) async {
        guard !isUpdatingLaundryState, let detail = state.detail else { return }
        guard detail.item.laundryState != newState else { return }
        isUpdatingLaundryState = true
        defer { isUpdatingLaundryState = false }
        actionError = nil

        var optimistic = detail
        optimistic.item.laundryState = newState
        apply(optimistic)

        do {
            var settled = detail
            settled.item = try await closetRepository.updateLaundryState(id: itemID, state: newState)
            apply(settled)
        } catch {
            await fail(error, rollingBackTo: detail)
        }
    }

    /// Soft-deletes the item by setting `archived_at` (spec §9 "soft
    /// deletion where appropriate"). The row is never deleted.
    ///
    /// `archiveItem(id:)` returns `Void`, so unlike the other two actions
    /// there is no updated row to fold in — and this view model does NOT
    /// invent one. Writing `archivedAt = .now` locally would put a client
    /// clock's timestamp into a column the database owns, and the screen
    /// is leaving anyway. Instead `didArchive` flips, the view dismisses,
    /// and the closet list re-reads on appear — where the item is already
    /// absent, because `fetchItems()` filters archived rows.
    ///
    /// Failure is the interesting path: nothing has changed, the screen
    /// stays where it is, and `actionError` carries the reason. A screen
    /// that dismissed on a failed archive would tell a man his jacket was
    /// gone when it is still there.
    public func archive() async {
        guard !isArchiving, state.detail != nil else { return }
        isArchiving = true
        defer { isArchiving = false }
        actionError = nil

        do {
            try await closetRepository.archiveItem(id: itemID)
            didArchive = true
        } catch let error as AstraError {
            actionError = error
            isOffline = await networkMonitor.isOffline()
        } catch {
            actionError = AstraError(category: .unknown, message: error.localizedDescription)
            isOffline = await networkMonitor.isOffline()
        }
    }

    /// Folds the editor's saved row back in without a re-fetch.
    ///
    /// `ClosetItemFormViewModel.onSaved` hands back the item the
    /// repository actually persisted, so re-reading it would be a round
    /// trip whose answer we already hold — and a round trip that can fail,
    /// which would leave a successful save looking like a broken screen.
    /// Photographs are untouched: the editor does not own them, so
    /// `images`/`imageURLs` carry over unchanged.
    public func applyEditedItem(_ item: ClosetItem) {
        guard var detail = state.detail else { return }
        detail.item = item
        apply(detail)
        savedEditCount += 1
    }

    /// Incremented every time the editor reports a save.
    ///
    /// The detail screen watches this to close the edit sheet. A `Bool`
    /// would work exactly once and then leave the second edit's sheet
    /// open; a counter is monotonic, so `onChange` fires every time. It is
    /// deliberately not a "sheet is presented" flag — this view model does
    /// not know or care that the editor is presented as a sheet.
    public private(set) var savedEditCount = 0

    public func clearActionError() {
        actionError = nil
    }

    /// Rolls the optimistic edit back and reports why.
    ///
    /// Both halves are load-bearing. Without the rollback the screen keeps
    /// showing a wear count the database does not have, which is the one
    /// failure mode worse than an error message. Without the message the
    /// number would silently jump back and read as a bug.
    ///
    /// Factored out rather than repeating the
    /// `catch let error as AstraError { … } catch { … }` pair in two
    /// actions; the mapping it performs is identical to that idiom, which
    /// `load()` and `archive()` still use directly.
    private func fail(_ error: Error, rollingBackTo detail: ItemDetail) async {
        apply(detail)
        actionError = (error as? AstraError)
            ?? AstraError(category: .unknown, message: error.localizedDescription)
        isOffline = await networkMonitor.isOffline()
    }
}

// MARK: - Presentation copy

/// What the cost-per-wear row says.
///
/// `CostPerWearCalculator.costPerWear` returns one `nil` for three
/// different reasons — no price on file, a negative price, and never worn
/// — and its own doc comment is explicit that `nil` means UNKNOWN, not
/// free and not infinite. Those causes are distinguishable at this call
/// site, and they are not the same sentence to the man reading them: one
/// is a fact about his wardrobe, the other is a field he can fill in. This
/// enum is what keeps them apart, and it is why the screen never renders
/// "—", "$0.00" or "∞".
public enum CostPerWearDisplay: Equatable, Sendable {
    /// A real figure, already formatted in the item's own currency.
    case amount(String)
    /// A price is on file; the garment has never been worn. Nothing to
    /// fix — the number simply does not exist yet.
    case notYetWorn
    /// No usable purchase price. The one the user can act on.
    case noPriceOnFile

    public var text: String {
        switch self {
        case .amount(let formatted):
            formatted
        case .notYetWorn:
            String(localized: "Not yet worn", comment: "Cost per wear is undefined because the garment has never been worn")
        case .noPriceOnFile:
            String(localized: "Add a price to see cost per wear", comment: "Cost per wear is undefined because no purchase price is recorded")
        }
    }
}

/// Formatting for the item detail screen's derived copy.
///
/// PROMOTION NOTE. `currency(_:code:)` is a general currency formatter and
/// `Core/Utilities/` is where it belongs, alongside
/// `DateAndWeatherFormatting.swift` and `MeasurementFormatting.swift` —
/// there is no currency formatter there today. It lives here because this
/// ticket does not own that directory. The moment a second surface needs
/// it (closet metrics' "estimated closet value" and the §6.19 product
/// decision page both will) it should move to
/// `Core/Utilities/CurrencyFormatting.swift` rather than be copied.
public enum ClosetItemDetailCopy {

    /// Which of the three cost-per-wear sentences this item gets.
    ///
    /// Price is checked before wear count on purpose. When BOTH are
    /// missing, "Add a price" is the one that leads somewhere: he supplies
    /// the price, wears the thing, and the number appears. Leading with
    /// "Not yet worn" would be true, useless, and would hide the field he
    /// could actually fill in.
    public static func costPerWear(for item: ClosetItem) -> CostPerWearDisplay {
        if let value = CostPerWearCalculator.costPerWear(pricePaid: item.pricePaid, wearCount: item.wearCount) {
            return .amount(currency(value, code: item.currency ?? Self.fallbackCurrencyCode))
        }
        guard let pricePaid = item.pricePaid, pricePaid >= 0 else { return .noPriceOnFile }
        return .notYetWorn
    }

    /// `closet_items.currency` is nullable and older rows predate it being
    /// written at all, so a fallback is required. USD rather than the
    /// device locale's currency: the number came from somewhere, and
    /// relabelling a recorded amount as £ because the phone is in London
    /// would be a quiet, confident lie about what he paid.
    public static let fallbackCurrencyCode = "USD"

    /// Deliberately does not force two decimal places. `.currency(code:)`
    /// already uses each currency's own minor-unit count, and a hardcoded
    /// `.fractionLength(2)` would render ¥1,200 as ¥1,200.00.
    public static func currency(_ amount: Decimal, code: String) -> String {
        amount.formatted(.currency(code: code))
    }

    /// Purchase date reads as an absolute date — it is a record of a
    /// transaction, and "2 years ago" is not what a receipt says.
    public static func purchaseDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Last worn reads as a relative date — "3 weeks ago" is the form the
    /// question is actually asked in ("have I worn this recently?"), and
    /// an absolute date makes the reader do the arithmetic.
    ///
    /// The empty case is "Never" rather than "Not yet worn" on purpose:
    /// cost per wear sits two rows below and already says "Not yet worn",
    /// and two adjacent rows answering different questions with the same
    /// sentence reads as a rendering bug.
    public static func lastWorn(_ date: Date?) -> String {
        guard let date else {
            return String(localized: "Never", comment: "The garment has no recorded wear yet")
        }
        return date.formatted(.relative(presentation: .named))
    }

    public static func wearCount(_ count: Int) -> String {
        String(localized: "^[\(count) wear](inflect: true)", comment: "How many times a garment has been worn")
    }

    /// How many of the optional §6.15 fields are still blank.
    ///
    /// Drives the single "add the rest" affordance under the field groups.
    /// Empty rows are omitted from this screen rather than rendered as
    /// placeholders (see `ClosetItemDetailView`), which is right for the
    /// reading experience but would otherwise make an under-filled item
    /// silently indistinguishable from a complete one — this count is what
    /// keeps that honest without printing nine dashes.
    public static func unfilledDetailCount(for item: ClosetItem) -> Int {
        let filled: [Bool] = [
            item.brand?.isEmpty == false,
            item.subcategory?.isEmpty == false,
            item.primaryColor?.isEmpty == false,
            !item.secondaryColors.isEmpty,
            item.pattern != nil,
            !item.material.isEmpty,
            item.size?.isEmpty == false,
            item.fit != nil,
            item.condition != nil,
            !item.seasonality.isEmpty,
            item.purchaseDate != nil,
            item.pricePaid != nil,
            item.retailer?.isEmpty == false,
            item.productURL != nil
        ]
        return filled.filter { !$0 }.count
    }

    public static func unfilledDetailPrompt(count: Int) -> String {
        String(localized: "^[\(count) detail](inflect: true) still blank", comment: "How many optional garment fields have no value yet")
    }
}
