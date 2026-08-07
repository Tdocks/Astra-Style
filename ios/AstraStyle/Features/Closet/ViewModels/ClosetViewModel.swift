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
//  SCOPE. This file backs the header, the category tiles, the grids, the
//  metrics row and the filter panel. The prediction the first draft of
//  this header made held: client-side narrowing funnels through one place
//  (`narrowed(_:)`), so the filter set arrived as a second predicate
//  beside the search predicate rather than as a new pipeline. Which of
//  the three view modes is on screen is NOT here — that is a display
//  preference belonging to the screen that draws it, persisted in
//  `@AppStorage` by `ClosetView`, and putting it on a view model that
//  every closet screen builds its own copy of would have made the two
//  closet screens disagree about a choice the user made once.
//
//  THREE DERIVED COLLECTIONS, NOT ONE, AND THE MIDDLE ONE EXISTS FOR THE
//  PANEL. `allItems` is the closet; `visibleItems` is search AND filters;
//  `searchNarrowedItems` is search WITHOUT filters, and it is what the
//  filter panel is built from. The panel's chips and its match count must
//  both be answered against a scope the user's own filter taps cannot
//  move, or every tap deletes chips from under his finger — see
//  `ClosetFilterOptions`'s header, which argues that call-site decision
//  in full.
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

    /// Why a grid has nothing in it. Four genuinely different situations
    /// that a single "nothing here" state would flatten into one wrong
    /// sentence — spec §21 fixes the copy for the first of them and it
    /// does not fit the other three.
    public enum EmptyReason: Equatable, Sendable {
        /// The whole closet is empty. This is the state spec §21 writes
        /// the copy for.
        case closetIsEmpty
        /// The closet has garments, but none in this category.
        case categoryIsEmpty(ClothingCategory)
        /// The closet has garments in scope, but none of them match what
        /// the user typed.
        case noSearchMatches(query: String)
        /// The closet has garments in scope, but the filter set excludes
        /// every one of them.
        ///
        /// Carries no payload, unlike `noSearchMatches`. A query is one
        /// short string and quoting it back names the mistake ("nothing
        /// matches 'navy jkt'"); a filter set is up to eight facets and
        /// any number of values, and a sentence reciting them would be
        /// longer than the panel that sets them — which the user can
        /// reopen, where every active facet is already listed with its
        /// own Clear.
        case noFilterMatches
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

    /// Spec §6.14's eight filter facets. `ClosetFilterPanelView` binds
    /// straight to this and every toggle lands on the screen behind the
    /// sheet immediately — there is no Apply step and no draft to lose,
    /// which is why this is a plain `var` rather than something the panel
    /// has to hand back.
    ///
    /// Mutable from outside for that reason alone. Everything derived
    /// from it below is a computed property, so there is no cache a
    /// direct write could leave stale.
    public var filters = ClosetFilters()

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
    /// isolation boundary everywhere else in the app, and because taking
    /// the store itself would drag a live
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

    /// Turns every facet off, leaving the search query alone.
    ///
    /// Deliberately not "clear everything": the two narrowings are set by
    /// two different controls and the man who taps this has been shown a
    /// sentence about his filters. Wiping his query as well would undo
    /// something he did not ask to undo, and he would have no way to tell
    /// which of the two changes put the garments back.
    public func clearFilters() {
        filters.clear()
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
    /// fetch will put it: `LiveClosetRepository.fetchItems()` orders by
    /// `created_at` descending, so a new garment appearing
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

    /// Every garment in the closet, ignoring both the search field and
    /// the filter set.
    public var allItems: [ClosetItem] { state.items }

    /// The closet narrowed by whatever the user has typed AND by whatever
    /// he has filtered. This is the single narrowing seam — both
    /// predicates live inside `narrowed(_:)`, not in parallel pipelines.
    public var visibleItems: [ClosetItem] { narrowed(state.items) }

    /// The closet narrowed by the search query and by nothing else.
    ///
    /// THIS IS THE SCOPE THE FILTER PANEL IS BUILT FROM, and it exists
    /// because neither of the other two collections can do that job.
    /// `allItems` would offer chips for brands the query has already
    /// excluded, so a man searching "navy" would be shown every label he
    /// owns. `visibleItems` would delete the chip he just tapped: the
    /// moment he selects a brand, every other brand covers zero of the
    /// remaining garments and vanishes, so the panel empties itself as he
    /// uses it. Search-narrowed and filter-free is the one scope that
    /// holds still for as long as the sheet is open, because the only
    /// control that could move it — the search field — is behind the
    /// sheet and out of reach.
    public var searchNarrowedItems: [ClosetItem] { searchNarrowed(state.items) }

    /// Which of spec §6.14's filter values this closet can actually offer,
    /// derived from `searchNarrowedItems` for the reason argued there and
    /// in `ClosetFilterOptions`'s own header.
    public var filterOptions: ClosetFilterOptions {
        ClosetFilterOptions.derive(from: searchNarrowedItems)
    }

    /// Spec §6.14's metrics block.
    ///
    /// COMPUTED OVER `allItems`, NOT `visibleItems`, AND THAT IS A
    /// DELIBERATE BREAK WITH THE TILE COUNTS BESIDE IT.
    /// `count(in:)` two properties down is search-aware, and it has to
    /// be: a category tile is a DOOR, and a number on a door that is not
    /// the number of garments behind it is a lie the user discovers by
    /// tapping. A metric is not a door. Nothing is behind "Estimated
    /// value" except the figure itself, and the two tiles that do name a
    /// garment resolve it by id, so they stay reachable whatever the
    /// query says.
    ///
    /// What settles it is what the labels claim. "Estimated closet value"
    /// is a statement about the wardrobe, and a total that falls from
    /// £14,000 to £180 because a man typed three letters into a search
    /// field reads as money going missing rather than as a filter
    /// working. "Average cost per wear" over a query is an average of
    /// whatever the query happened to catch, which is not a figure about
    /// anything. And "Most worn" narrowed to a search is the most-worn
    /// thing matching that search — a different question, asked under the
    /// old question's label.
    ///
    /// So: counts on navigation controls follow the query; figures about
    /// the wardrobe do not. Filters are treated identically, for the same
    /// reason — they are a narrower scope, not a different wardrobe.
    public var metrics: ClosetMetrics {
        ClosetMetrics.compute(for: allItems)
    }

    public func items(in category: ClothingCategory) -> [ClosetItem] {
        narrowed(state.items.filter { $0.category == category })
    }

    /// The count shown on a category tile. Reflects the active search and
    /// the active filters, so the number on the tile and the number of
    /// garments behind it are never two different facts.
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

        // A CATEGORY THE MAN OWNS NOTHING IN IS EMPTY FOR THAT REASON, AND
        // NOT FOR WHATEVER ELSE HAPPENS TO BE SWITCHED ON.
        //
        // This is checked before the query and the filter set, because it
        // is the only one of the three that is true regardless of them.
        // Reaching Shoes with a filter active used to report
        // `noFilterMatches` on a closet containing no shoes at all — the
        // man read "you own pieces in each of those, but none in all of
        // them at once", pressed Clear Filters, and the grid stayed empty
        // before finally admitting he owns no shoes. The sentence was
        // untrue of that scope and the button it came with put nothing
        // back, which is the dead control spec §22 rules out wearing the
        // costume of a recovery.
        if let category, !state.items.contains(where: { $0.category == category }) {
            return .categoryIsEmpty(category)
        }

        // PRECEDENCE, WHEN A QUERY AND A FILTER SET COULD BOTH EXPLAIN IT.
        // The query wins, for two reasons that point the same way.
        //
        // It is the more specific act. A typed query is aimed at one
        // garment, and the sentence it produces can quote the typo back —
        // "nothing matches 'navy jkt'" names the actual mistake, which no
        // sentence about a filter set can do. A filter set is a standing
        // scope the user configured earlier, in a sheet he has since
        // dismissed; the query is live under his finger in a field that
        // is still on screen.
        //
        // And neither recovery is a dead control when it does not finish
        // the job. Clearing the query on a screen that is still
        // filter-empty does not leave the same screen behind: the field
        // empties, the sentence changes, and the state becomes
        // `noFilterMatches` with its own Clear Filters underneath it. Two
        // visible steps, each of which plainly did something (spec §22),
        // rather than one control that has to guess which of two things
        // the user meant.
        //
        // BUT THE QUERY ONLY WINS WHEN IT COULD ACTUALLY BE THE CAUSE.
        // Precedence is a rule for the case where BOTH explain the
        // emptiness, and asking `isSearching` does not test that — it only
        // asks whether a query exists. A man filtering to Aspesi and then
        // typing "shirt" over a closet holding two shirts by other houses
        // was told "Nothing in your closet matches 'shirt'", which is
        // false, and Clear Search then handed him back garments that are
        // not shirts. So the branch asks the question it means: does the
        // query, on its own, empty this scope? If it does not, the filters
        // did, and the next branch says so.
        let scopeSource = category.map { category in state.items.filter { $0.category == category } } ?? state.items
        if isSearching, searchNarrowed(scopeSource).isEmpty {
            return .noSearchMatches(query: trimmedQuery)
        }
        if !filters.isEmpty {
            return .noFilterMatches
        }
        // A non-empty closet with no active search and no active filters
        // can only be empty in scope when that scope is a category.
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

    /// The one place client-side narrowing happens: filters, then search.
    ///
    /// FILTERS FIRST BECAUSE THEY ARE THE CHEAPER PREDICATE, and the two
    /// commute so the order is free to choose. Both are per-item
    /// predicates with no cross-item state, so filter-then-search and
    /// search-then-filter select exactly the same garments in exactly the
    /// same order; only the amount of work differs.
    ///
    /// A filter facet is a `Set.contains` on a value already in hand, the
    /// chain short-circuits on the first facet a garment fails, and an
    /// empty filter set returns the very array it was handed without
    /// touching an element (`ClosetFilters.apply(to:)` guarantees that in
    /// writing). Search is `localizedCaseInsensitiveContains` — a
    /// locale-aware Unicode substring search — run over up to five
    /// strings per garment, and it cannot stop early on a garment that
    /// matches nothing until it has tried all five. So the cheap
    /// predicate runs first and the expensive one runs over whatever
    /// survives it.
    private func narrowed(_ items: [ClosetItem]) -> [ClosetItem] {
        searchNarrowed(filters.apply(to: items))
    }

    /// The search half of `narrowed(_:)`, on its own.
    ///
    /// Split out rather than inlined because `searchNarrowedItems` — the
    /// scope the filter panel is built from — needs exactly this and not
    /// the filtered result. Two callers, one implementation, so the panel
    /// and the grid can never disagree about what the query means.
    private func searchNarrowed(_ items: [ClosetItem]) -> [ClosetItem] {
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
