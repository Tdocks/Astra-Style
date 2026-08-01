//
//  ClosetViewModel.swift
//  AstraStyle
//
//  Drives the Closet tab overview (spec §6.14 "Closet overview") and the
//  per-category grid pushed from it. Patterned deliberately on
//  Features/Home/ViewModels/HomeViewModel.swift, which is this codebase's
//  reference view model: an explicit `ViewState` covering loading /
//  loaded / empty / failed, a separate `isOffline` flag (offline is
//  orthogonal — a cached closet stays viewable per spec §7), per-action
//  in-flight booleans, protocol-only dependencies, and zero networking
//  anywhere above this file.
//
//  SCOPE. This file backs the header, the category tiles and the grids
//  only. The metrics row and the three view modes, and the filter panel,
//  are separate tickets. Nothing here needs restructuring to add them:
//  client-side narrowing already funnels through one place
//  (`narrowed(_:)`), so a filter set becomes a second predicate beside the
//  search predicate rather than a new pipeline.
//
//  WHY `fetchWardrobeScore()` IS NOT CALLED. It throws
//  `AstraError.unimplemented` unconditionally today — there is no
//  `wardrobe_scores` table (see docs/03-progress.md). Calling it to render
//  a score would put a permanent, unwinnable error on the closet's first
//  screen.
//
//  DEGRADE A MODULE, NEVER THE SCREEN. That is what
//  `AstraError.Category.unimplemented` exists for, and this file applies
//  the rule where it actually bites today: image resolution. If signing
//  fails — because the feature is missing, because the user is offline,
//  because one photograph was deleted — the garments, their names, brands
//  and counts stay on screen and only the photographs are absent, which
//  `AstraRemoteImage` already renders as a garment with no picture rather
//  than as a broken one.
//
//  `fetchItems()` is deliberately NOT given that treatment. It is the
//  screen's content, not a module beside it, and mapping "this is not
//  built" onto "you own nothing" would tell the user something false about
//  his own wardrobe. It fails as a failure — and the error view reads
//  `AstraError.isRetryable`, which is already `false` for
//  `.unimplemented`, so a failure nobody can retry never grows a Try Again
//  button (spec §22: no dead buttons, including in error states).
//
//  IMAGES: WHY THE TILES ASK, RATHER THAN THE LOAD PUSHING.
//  `ClosetRepository.fetchImages(forItem:)` is per item, so learning the
//  storage paths for a whole closet is N calls no matter who makes them —
//  and `ClosetImageURLResolving.resolve(storagePaths:)` can only batch
//  paths it has been given. Resolving the whole closet up front therefore
//  costs N round trips before the first tile can draw, and most of them
//  are for garments the user will never scroll to.
//
//  So resolution is lazy and tile-driven: a tile calls
//  `imageNeeded(for:)` as it appears, which is a synchronous registration,
//  not a request. Every tile that appears in the same frame registers
//  before the first `await` resumes, and the scheduled pass then resolves
//  that whole screenful with N path lookups (concurrent, and each one
//  failing independently) followed by exactly ONE
//  `resolve(storagePaths:)`. Scrolling adds the next screenful to the same
//  pending set. The result is: no round trip for a garment nobody looked
//  at, and never one signing request per tile.
//
//  THIS SCREEN LOGS NOTHING ITSELF. Spec §18's event list has no "closet
//  browsed" or "category opened" event, and inventing one here would put a
//  name on the wire that the spec does not define.
//  `Features/Slice/SliceViewModel.swift` omits it for the same reason. The
//  closet event that does exist — `closet_item_added` — belongs to the
//  add/edit form, which is why the `analyticsClient` this type holds is
//  never used by this type: it is forwarded to the form built by
//  `makeAddItemViewModel()` and nowhere else.
//
//  THE ADD DOOR. `makeAddItemViewModel()` is what makes P3-CLOSET-08's
//  form reachable — before it, `ClosetItemFormViewModel.adding(...)` had
//  no call site anywhere in the app and the Closet tab's only way in was a
//  scan button in front of a scanner that has not shipped. It lives here
//  rather than in `ClosetView` for the reason
//  `ClosetItemDetailView.makeEditorViewModel(for:)` is the way it is —
//  the closet screens build the form out of the dependencies their own
//  view model was handed, instead of a `View` reaching into `AppContainer`
//  — and putting it on the view model additionally means the wiring that
//  actually bit this form (an add path with no `currentUserID` provider,
//  which compiles and then fails at submit with an auth error) is covered
//  by a unit test rather than only by tapping the button.
//

import Foundation
import Observation

@MainActor
@Observable
public final class ClosetViewModel {

    // MARK: - State

    public enum ViewState: Equatable {
        case loading
        /// The closet has at least one item. The payload is the whole
        /// unfiltered closet; search and per-category narrowing are
        /// derived, never stored, so there is one source of truth.
        case loaded([ClosetItem])
        /// Fetched successfully and the closet is genuinely empty. Carries
        /// the (empty) collection rather than nothing so that call sites
        /// can treat `.loaded` and `.empty` interchangeably where the
        /// distinction does not matter — the same shape `HomeViewModel`
        /// fixed.
        case empty([ClosetItem])
        case failed(AstraError)

        /// Hand-written rather than synthesised, and deliberately compares
        /// item IDENTITY rather than every field of every garment.
        ///
        /// The question this answers is "is the screen showing the same
        /// garments, in the same order" — which is what an animation or a
        /// test wants. It is not a content diff: a wear count bumped from
        /// the item-detail screen changes a tile's text, and SwiftUI
        /// repaints that through `@Observable` tracking regardless of what
        /// this operator says. Comparing every field would additionally
        /// make this O(fields x items) on a path that runs on every state
        /// write.
        public static func == (lhs: ViewState, rhs: ViewState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading):
                true
            case (.loaded(let left), .loaded(let right)), (.empty(let left), .empty(let right)):
                left.map(\.id) == right.map(\.id)
            case (.failed(let left), .failed(let right)):
                left == right
            default:
                false
            }
        }

        /// Every garment the last successful fetch returned, unfiltered.
        var items: [ClosetItem] {
            switch self {
            case .loaded(let items), .empty(let items): items
            case .loading, .failed: []
            }
        }

        /// The offline banner belongs over content that is actually
        /// rendering. The skeleton and the error screen already state
        /// their own status, and stacking "you're offline" on top of
        /// "you're offline" is how a screen ends up saying it twice.
        var showsOfflineBannerWhenStale: Bool {
            switch self {
            case .loaded, .empty: true
            case .loading, .failed: false
            }
        }

        /// Whether there is anything for a search field to narrow.
        ///
        /// A search field above a skeleton, an error, or a closet with
        /// nothing in it is a control that cannot do anything, which is
        /// the dead control spec §22 rules out — so the field is not drawn
        /// in those three states rather than drawn and inert.
        var hasSearchableContent: Bool {
            switch self {
            case .loaded: true
            case .loading, .empty, .failed: false
            }
        }
    }

    /// Why a grid has nothing in it. Three genuinely different situations
    /// that a single "nothing here" state would flatten into one wrong
    /// sentence — spec §21 fixes the copy for the first of them and it
    /// does not fit the other two.
    public enum EmptyReason: Equatable, Sendable {
        /// The whole closet is empty. This is the state spec §21 writes
        /// the copy for.
        case closetIsEmpty
        /// The closet has garments, but none in this category.
        case categoryIsEmpty(ClothingCategory)
        /// The closet has garments in scope, but none of them match what
        /// the user typed.
        case noSearchMatches(query: String)
    }

    public private(set) var state: ViewState = .loading

    /// Independent of `state`. Spec §7 keeps a cached closet viewable
    /// offline, so "offline" is a banner over real content, not a
    /// replacement for it.
    public private(set) var isOffline = false

    /// The header's search field binds straight to this. Narrowing is
    /// client-side against the already-fetched closet — there is no
    /// server-side closet search endpoint in spec §14, and a wardrobe is
    /// small enough that filtering in memory is both instant and correct
    /// while offline.
    public var searchText: String = ""

    /// Resolved, displayable image URLs keyed by `ClosetItem.id`. Absent
    /// means "not resolved yet, or this garment has no photograph" —
    /// `AstraRemoteImage` renders both identically and on purpose.
    public private(set) var imageURLsByItemID: [UUID: URL] = [:]

    public private(set) var isRefreshing = false
    public private(set) var isResolvingImages = false

    // MARK: - Dependencies

    private let closetRepository: ClosetRepository
    private let imageURLResolver: ClosetImageURLResolving
    private let networkMonitor: NetworkReachabilityMonitoring

    /// Who the garment being added belongs to. A closure rather than a
    /// `SessionStore` because that is how this fact already crosses an
    /// isolation boundary everywhere else in the app (`AppContainer` hands
    /// `GuestClosetRepository` a `currentGuestUserID` closure the same
    /// way), and because taking the store itself would drag a live
    /// Supabase client into every unit test of a screen that makes no auth
    /// call.
    ///
    /// Optional, and defaulted to `nil`, only so the previews and the
    /// per-category screens that never present the form need not supply
    /// one. A `nil` here is not silent: `ClosetItemFormViewModel`'s own
    /// `init` logs a warning the moment an add form is built without a
    /// provider.
    private let currentUserID: (@Sendable () async -> UUID?)?

    /// Forwarded to the add form so `closet_item_added` (spec §18) is
    /// logged. Never used by this type — see this file's header.
    private let analyticsClient: any AnalyticsClient

    // MARK: - Image resolution bookkeeping

    /// Registered by a tile, not yet resolved.
    private var pendingImageItemIDs: Set<UUID> = []
    /// Already attempted, whether or not it produced a URL. Stops a
    /// garment with no photograph from being looked up again every time
    /// its tile scrolls back into view.
    private var attemptedImageItemIDs: Set<UUID> = []
    /// The pass currently coalescing registrations, if one is running.
    /// Held rather than fired and forgotten so `awaitPendingImageResolution()`
    /// can be a real guarantee instead of a sleep.
    private var imageResolutionTask: Task<Void, Never>?

    public init(
        closetRepository: ClosetRepository,
        imageURLResolver: ClosetImageURLResolving,
        currentUserID: (@Sendable () async -> UUID?)? = nil,
        analyticsClient: any AnalyticsClient = NoOpAnalyticsClient(),
        networkMonitor: NetworkReachabilityMonitoring = SystemNetworkReachabilityMonitor()
    ) {
        self.closetRepository = closetRepository
        self.imageURLResolver = imageURLResolver
        self.currentUserID = currentUserID
        self.analyticsClient = analyticsClient
        self.networkMonitor = networkMonitor
    }

    // MARK: - Lifecycle

    public func onAppear() async {
        isOffline = await networkMonitor.isOffline()
        guard case .loading = state else { return }
        await load(showingSkeleton: true)
    }

    /// Pull-to-refresh. Deliberately does NOT drop back to the skeleton:
    /// `.refreshable` draws its own in-flight indicator directly above the
    /// content, and blanking the grid underneath it loses the user's
    /// scroll position and reads as the screen having crashed.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await load(showingSkeleton: false)
    }

    public func retry() async {
        await load(showingSkeleton: true)
    }

    public func clearSearch() {
        searchText = ""
    }

    // MARK: - Adding a garment (spec §6.15's editable fields, manual path)

    /// Builds the manual add form's view model, already wired to fold its
    /// result back into this screen.
    ///
    /// The mirror of `ClosetItemDetailView.makeEditorViewModel(for:)`, and
    /// the reason both exist rather than a `ClosetRoute` case: the form
    /// needs collaborators (`currentUserID`, the analytics client) that a
    /// route value cannot carry, and it is presented modally over the
    /// screen that has to show the result.
    ///
    /// `onSaved` captures only `self`, which is a `@MainActor` class and
    /// therefore `Sendable`. Weakly, because the returned form outlives
    /// nothing here but is held by a sheet whose lifetime SwiftUI owns —
    /// a strong capture would be a retain cycle the moment a view holds
    /// both.
    public func makeAddItemViewModel() -> ClosetItemFormViewModel {
        let form = ClosetItemFormViewModel.adding(
            closetRepository: closetRepository,
            currentUserID: currentUserID,
            analyticsClient: analyticsClient
        )
        form.onSaved = { [weak self] item in
            self?.insertSavedItem(item)
        }
        return form
    }

    /// Folds a just-created garment into the loaded closet.
    ///
    /// Preferred over a re-fetch for the same reason
    /// `ClosetItemDetailViewModel.applyEditedItem(_:)` is: `onSaved` hands
    /// back the row the repository actually persisted, so re-reading it
    /// would be a round trip whose answer we already hold — and one that
    /// can fail, which would make a successful save look like a broken
    /// screen.
    ///
    /// Inserted at the FRONT, not appended, because that is where the next
    /// fetch will put it: both closet stores order by `created_at`
    /// descending (`LiveClosetRepository.fetchItems()` and
    /// `SwiftDataGuestClosetStore.items(for:)`), so a new garment appearing
    /// at the top now and staying there after a refresh is the same list,
    /// not two.
    ///
    /// A search that the new garment does not match will hide it again
    /// immediately, and that is correct: `visibleItems` is derived, so the
    /// row is genuinely in the closet and the query is genuinely
    /// excluding it.
    public func insertSavedItem(_ item: ClosetItem) {
        switch state {
        case .loaded(var items), .empty(var items):
            // Guarded because `onSaved` fires once per successful submit
            // and the form stays open for a second one; nothing else can
            // deliver the same id twice, but a duplicated row in a
            // `ForEach` is a runtime warning rather than a compile error,
            // so it is cheaper to make impossible than to detect.
            guard !items.contains(where: { $0.id == item.id }) else { return }
            items.insert(item, at: 0)
            state = .loaded(items)

        case .loading, .failed:
            // There is nothing on screen to fold into — the closet either
            // has not loaded yet or failed to. Synthesising a one-item
            // `.loaded` here would tell a man his entire wardrobe is the
            // jumper he just typed in, so this re-reads instead. That is
            // also the one case where a refresh is the honest answer: a
            // failed load is exactly the state that needs retrying, and
            // the save proves the network is back.
            Task { await self.refresh() }
        }
    }

    // MARK: - Derived collections

    /// Every garment in the closet, ignoring the search field.
    public var allItems: [ClosetItem] { state.items }

    /// The closet narrowed by whatever the user has typed. This is the
    /// single narrowing seam: the filter panel becomes a second predicate
    /// inside `narrowed(_:)`, not a parallel pipeline.
    public var visibleItems: [ClosetItem] { narrowed(state.items) }

    public func items(in category: ClothingCategory) -> [ClosetItem] {
        narrowed(state.items.filter { $0.category == category })
    }

    /// The count shown on a category tile. Reflects the active search, so
    /// the number on the tile and the number of garments behind it are
    /// never two different facts.
    public func count(in category: ClothingCategory) -> Int {
        items(in: category).count
    }

    public var visibleItemCount: Int { visibleItems.count }

    public var totalItemCount: Int { state.items.count }

    public var isSearching: Bool { !trimmedQuery.isEmpty }

    /// Why the grid in `category` (or the whole-closet grid, when `nil`)
    /// has nothing to show — or `nil` when it does have something.
    public func emptyReason(for category: ClothingCategory?) -> EmptyReason? {
        switch state {
        case .loading, .failed:
            return nil
        case .empty, .loaded:
            break
        }

        guard !state.items.isEmpty else { return .closetIsEmpty }

        let scoped = category.map { items(in: $0) } ?? visibleItems
        guard scoped.isEmpty else { return nil }

        if isSearching {
            return .noSearchMatches(query: trimmedQuery)
        }
        // A non-empty closet with no active search can only be empty in
        // scope when that scope is a category.
        return category.map(EmptyReason.categoryIsEmpty)
    }

    public func imageURL(for item: ClosetItem) -> URL? {
        imageURLsByItemID[item.id]
    }

    // MARK: - Image resolution

    /// Registers a garment whose photograph is now on screen.
    ///
    /// Synchronous by design — see this file's header. A whole screenful
    /// of tiles registers within one frame, and the pass scheduled by the
    /// first of them resolves all of them together.
    public func imageNeeded(for item: ClosetItem) {
        guard imageURLsByItemID[item.id] == nil, !attemptedImageItemIDs.contains(item.id) else { return }
        pendingImageItemIDs.insert(item.id)
        guard imageResolutionTask == nil else { return }
        imageResolutionTask = Task {
            // One hop, so every tile that appeared in this frame has had a
            // chance to register before the pending set is drained.
            await Task.yield()
            await drainPendingImages()
            imageResolutionTask = nil
        }
    }

    /// Waits for the in-flight resolution pass, if any, to finish.
    ///
    /// The pass is scheduled rather than awaited at the call site — a tile
    /// appearing cannot be `async` — so this is how anything that needs to
    /// know the pass is done finds out, instead of guessing with a sleep.
    public func awaitPendingImageResolution() async {
        await imageResolutionTask?.value
    }

    /// Resolves everything registered so far.
    ///
    /// Public so a test can drive the pass deterministically rather than
    /// racing the scheduler.
    public func drainPendingImages() async {
        guard !isResolvingImages else { return }
        isResolvingImages = true
        defer { isResolvingImages = false }

        while !pendingImageItemIDs.isEmpty {
            // A reload cancels the pass in flight: the URLs it is about to
            // write describe a closet that has already been replaced.
            guard !Task.isCancelled else { return }
            let batch = pendingImageItemIDs
            pendingImageItemIDs.removeAll()
            attemptedImageItemIDs.formUnion(batch)
            await resolveImages(forItemIDs: batch)
        }
    }

    /// N path lookups, then exactly one signing request.
    private func resolveImages(forItemIDs itemIDs: Set<UUID>) async {
        // Captured as a local so the child tasks below capture the
        // already-`Sendable` repository rather than this `@MainActor`
        // view model.
        let repository = closetRepository

        let pathsByItemID = await withTaskGroup(of: (UUID, String?).self, returning: [UUID: String].self) { group in
            for itemID in itemIDs {
                group.addTask {
                    // One garment's images failing must not take the rest
                    // of the screenful with it — the tile falls back to
                    // "no photo", which is what the user would see anyway.
                    let images = (try? await repository.fetchImages(forItem: itemID)) ?? []
                    let primary = images.first { $0.isPrimary } ?? images.first
                    return (itemID, primary?.displayStoragePath)
                }
            }
            var collected: [UUID: String] = [:]
            for await (itemID, path) in group {
                if let path {
                    collected[itemID] = path
                }
            }
            return collected
        }

        guard !pathsByItemID.isEmpty else { return }

        do {
            // THE batch call. One request for the whole screenful, not one
            // per tile — see `ClosetImageURLResolving`'s own header for
            // why the two-method protocol exists.
            let signed = try await imageURLResolver.resolve(storagePaths: Array(pathsByItemID.values))
            for (itemID, path) in pathsByItemID {
                if let url = signed[path] {
                    imageURLsByItemID[itemID] = url
                }
            }
        } catch {
            // Signing failing is not the closet failing to load. The
            // garments, their names, brands and counts are all still on
            // screen and still correct; only the photographs are missing,
            // which the tiles already render honestly. Surface it as the
            // connectivity condition it almost always is rather than
            // replacing a working screen with an error page.
            isOffline = await networkMonitor.isOffline()
        }
    }

    // MARK: - Loading

    private func load(showingSkeleton: Bool) async {
        isOffline = await networkMonitor.isOffline()
        if showingSkeleton {
            state = .loading
        }
        do {
            let items = try await closetRepository.fetchItems()
            resetImageResolution()
            state = items.isEmpty ? .empty(items) : .loaded(items)
        } catch let error as AstraError {
            state = .failed(error)
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }

    /// A reload can mean a garment's primary photograph changed, so the
    /// resolved URLs and the "already tried this one" set are both dropped
    /// rather than carried forward.
    private func resetImageResolution() {
        imageResolutionTask?.cancel()
        imageResolutionTask = nil
        imageURLsByItemID.removeAll()
        attemptedImageItemIDs.removeAll()
        pendingImageItemIDs.removeAll()
    }

    // MARK: - Narrowing

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The one place client-side narrowing happens.
    private func narrowed(_ items: [ClosetItem]) -> [ClosetItem] {
        let query = trimmedQuery
        guard !query.isEmpty else { return items }
        return items.filter { matches($0, query: query) }
    }

    /// Matches the fields a man would actually type: what he calls it, who
    /// made it, what kind of thing it is, and what colour it is.
    /// `localizedCaseInsensitiveContains` rather than a lowercased
    /// comparison so accents and non-Latin scripts fold the way the user's
    /// locale folds them.
    private func matches(_ item: ClosetItem, query: String) -> Bool {
        var haystack = [item.name]
        if let brand = item.brand { haystack.append(brand) }
        if let subcategory = item.subcategory { haystack.append(subcategory) }
        if let primaryColor = item.primaryColor { haystack.append(primaryColor) }
        haystack.append(contentsOf: item.secondaryColors)
        return haystack.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
