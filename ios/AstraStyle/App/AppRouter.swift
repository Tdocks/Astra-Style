//
//  AppRouter.swift
//  AstraStyle
//
//  Owns top-level app routing state (spec §27 `AppRouteState`) plus one
//  independent `NavigationPath`-equivalent stack per tab, so switching tabs
//  never loses a tab's navigation position (spec §4: "Preserve tab
//  navigation state").
//

import Foundation
import Observation

/// Top-level routing state shown by `RootView`.
///
/// Mirrors spec §27 exactly:
/// - `.launching`   splash / session restoration in flight.
/// - `.signedOut`   no session; show Welcome/authentication (§6.2).
/// - `.onboarding`  authenticated but `onboarding_completed_at` is nil (§6.4-6.10).
/// - `.main`        authenticated and onboarded; show the five-tab shell (§4).
public enum AppRouteState: Equatable, Sendable {
    case launching
    case signedOut
    case onboarding
    case main
}

/// The five primary tabs, in tab-bar order (spec §4).
public enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case home
    case closet
    case studio
    case discover
    case shop
    case profile

    /// Tabs drawn in the bar. Unfinished chrome adds nothing extra today —
    /// Studio is on the dogfood bar.
    public static var chromeTabs: [AppTab] {
        AstraFeatureFlags.showsUnfinishedChrome ? Array(allCases) : dogfoodTabs
    }

    /// Home, Closet, Studio, Discover, Shop, Profile.
    public static let dogfoodTabs: [AppTab] = [
        .home, .closet, .studio, .discover, .shop, .profile,
    ]

    public var isShownInChrome: Bool {
        Self.chromeTabs.contains(self)
    }

    public var id: String { rawValue }

    /// String-Catalog-ready: the literal here is both the extraction key and
    /// the base-language value, matching Xcode's `.xcstrings` workflow. Run
    /// Product > Export Localizations (or let Xcode auto-generate
    /// `Localizable.xcstrings`) to pick these up — no separate key table.
    public var title: String {
        switch self {
        case .home: String(localized: "Home", comment: "Tab bar item: Kyra's Daily Brief")
        case .closet: String(localized: "Closet", comment: "Tab bar item: wardrobe")
        case .studio: String(localized: "Studio", comment: "Tab bar item: Style Studio")
        case .discover: String(localized: "Discover", comment: "Tab bar item: editorial content")
        case .shop: String(localized: "Shop", comment: "Tab bar item: curated catalog")
        case .profile: String(localized: "Profile", comment: "Tab bar item: profile and stats")
        }
    }

    /// SF Symbol shown inactive. Active state is rendered filled by the
    /// DesignSystem tab bar styling (gold indicates active per spec §3
    /// "Iconography").
    public var symbolName: String {
        switch self {
        case .home: "house"
        case .closet: "square.grid.2x2"
        case .studio: "camera.viewfinder"
        case .discover: "safari"
        case .shop: "bag"
        case .profile: "person.crop.circle"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .home: String(localized: "Home, Kyra's Daily Brief", comment: "VoiceOver label for the Home tab")
        case .closet: String(localized: "Closet", comment: "VoiceOver label for the Closet tab")
        case .studio: String(localized: "Style Studio", comment: "VoiceOver label for the Studio tab")
        case .discover: String(localized: "Discover", comment: "VoiceOver label for the Discover tab")
        case .shop: String(localized: "Shop, curated catalog", comment: "VoiceOver label for the Shop tab")
        case .profile: String(localized: "Profile", comment: "VoiceOver label for the Profile tab")
        }
    }
}

// MARK: - Per-tab typed routes

/// Destinations pushed on the Home tab's `NavigationStack`.
public enum HomeRoute: Hashable, Sendable {
    case outfitDetail(outfitID: UUID)
    case alternativeLooks(briefID: UUID)
    case kyraThread(threadID: UUID?)
    case occasionDetail(occasionID: UUID)
    case monthlyReview(month: Date)
    /// The Home "purchase opportunity" module (spec §6.11) links straight
    /// to a product's decision page (spec §6.19). Shopping owns the full
    /// feature (P6-SHOP); this route exists on `HomeRoute` rather than
    /// `ShoppingRoute` because it's reached from Home's own NavigationStack.
    case productDecision(candidateID: UUID)
}

/// Destinations pushed on the Closet tab's `NavigationStack`.
public enum ClosetRoute: Hashable, Sendable {
    case category(ClothingCategory)
    case itemDetail(itemID: UUID)
    /// A saved outfit, opened from the Closet's looks carousel.
    ///
    /// A second case rather than reusing `HomeRoute.outfitDetail`: each tab
    /// owns its own `NavigationStack` path, so pushing a `HomeRoute` onto
    /// `closetPath` would not resolve — `ClosetDestinationView` is the only
    /// thing that reads this stack.
    case outfitDetail(outfitID: UUID)
    case editItem(itemID: UUID)
    case scanner(mode: ScannerRoute)
    case colorSpectrum
    case filters
}

/// Destinations pushed on the Studio tab's `NavigationStack`.
public enum StudioRoute: Hashable, Sendable {
    case generation(generationID: UUID)
    case referenceCapture
    case compare(generationIDs: [UUID])
    case lookbook
}

/// Destinations pushed on the Discover tab's `NavigationStack`.
public enum DiscoverRoute: Hashable, Sendable {
    case lookbook(id: UUID)
    case productDecision(candidateID: UUID)
    case styleGuide(slug: String)
    case brandSpotlight(brand: String)
    case fitGuide(slug: String)
}

/// Destinations pushed on the Shop tab's `NavigationStack`.
public enum ShopRoute: Hashable, Sendable {
    case productDecision(candidateID: UUID)
}

/// Destinations pushed on the Profile tab's `NavigationStack`.
public enum ProfileRoute: Hashable, Sendable {
    case styleDNA
    case wardrobeScoreDetail
    case preferences
    case subscriptionManagement
    case privacyAndData
    case styleMemories
    case styleJourney
    case accountDeletion
}

/// Destinations pushed on the Scanner flow's `NavigationStack` (presented
/// modally per spec §4 "Present camera ... as modal flows").
public enum ScannerRoute: Hashable, Sendable {
    case singleItem
    case batchCloset
    case receiptLabel
    case outfitMirror
    case review(capturedImageID: UUID)
}

/// Destinations pushed on the Outfits builder flow.
public enum OutfitBuilderRoute: Hashable, Sendable {
    case builder(startingOutfitID: UUID?)
    case visualize(outfitID: UUID)
    case shopMissingItems(outfitID: UUID)
}

/// Destinations pushed on the Kyra conversation flow.
public enum KyraRoute: Hashable, Sendable {
    /// `nil` means a NEW conversation. The server creates the
    /// `kyra_threads` row on the first send (`POST /kyra/respond` with
    /// `thread_id: null` — `supabase/functions/kyra/README.md`), so the
    /// client cannot know the id before that response arrives. This case
    /// used to be non-optional and `startAskKyra` papered over it by
    /// minting a fresh `UUID()` — an id the database had never heard of,
    /// which the first send would then have posted as if it named a real
    /// thread. Optional is the honest shape.
    case thread(threadID: UUID?)
    case memories
    case productCard(productID: UUID)
}

/// Modal presentation surfaces, orthogonal to the five per-tab stacks
/// (spec §4: "Present camera, paywall, authentication, onboarding, and
/// full-screen visual generation as modal flows").
public enum AppModalRoute: Identifiable, Sendable {
    case scanner(ScannerRoute)
    case paywall(context: PaywallContext)
    case outfitBuilder(OutfitBuilderRoute)
    case studioGeneration(outfitID: UUID?)
    case askKyra(KyraRoute)
    case addOccasion
    case packingTrip

    public var id: String {
        switch self {
        case .scanner: "scanner"
        case .paywall: "paywall"
        case .outfitBuilder: "outfitBuilder"
        case .studioGeneration: "studioGeneration"
        case .askKyra: "askKyra"
        case .addOccasion: "addOccasion"
        case .packingTrip: "packingTrip"
        }
    }
}

/// `@Observable` root router. Injected into the environment alongside
/// `AppContainer` and read by `RootView`, `MainTabView`, and every feature's
/// `Routing/` coordinator.
@MainActor
@Observable
public final class AppRouter {

    /// Resets navigation automatically on any transition to `.signedOut`.
    ///
    /// Doing this in a `didSet` rather than at each sign-out call site is
    /// deliberate. There are several ways to become signed out — the user taps
    /// sign out, a refresh token is revoked server-side, account deletion
    /// completes — and only the first is a place anyone remembers to add
    /// clean-up code. Tying it to the state transition means every path is
    /// covered, including ones not written yet.
    public var routeState: AppRouteState = .launching {
        didSet {
            guard oldValue != routeState, routeState == .signedOut else { return }
            resetForSignOut()
        }
    }

    /// Hidden tabs (an older build, or a deep link) fall back to Home.
    public var selectedTab: AppTab = .home {
        didSet {
            if !selectedTab.isShownInChrome {
                selectedTab = .home
            }
        }
    }

    // Independent navigation stacks — one per tab — so switching tabs never
    // discards where the user was (spec §4).
    public var homePath: [HomeRoute] = []
    public var closetPath: [ClosetRoute] = []
    public var studioPath: [StudioRoute] = []
    public var discoverPath: [DiscoverRoute] = []
    public var shopPath: [ShopRoute] = []
    public var profilePath: [ProfileRoute] = []

    /// Active modal presentation, if any. Only one modal flow is presented
    /// at a time.
    public var presentedModal: AppModalRoute?

    public init() {}

    /// Where a freshly authenticated session goes next.
    ///
    /// Normally `.onboarding` — §27 routes an authenticated user with no
    /// `onboarding_completed_at` into §6.3–§6.10. `-astra-skip-onboarding`
    /// (Debug builds only, see `AstraFeatureFlags.skipsOnboarding`) sends it
    /// straight to `.main` instead, for UI tests whose subject is the tab shell.
    ///
    /// Computed here rather than at each `routeState = .onboarding` site so the
    /// two entry points (Apple, email) cannot drift apart — the same reason
    /// `resetForSignOut` hangs off the state transition above.
    public static var postAuthenticationRoute: AppRouteState {
        AstraFeatureFlags.skipsOnboarding ? .main : .onboarding
    }

    // MARK: - Convenience navigation

    public func push(_ route: HomeRoute) { homePath.append(route) }
    public func push(_ route: ClosetRoute) { closetPath.append(route) }
    public func push(_ route: StudioRoute) { studioPath.append(route) }
    public func push(_ route: DiscoverRoute) { discoverPath.append(route) }
    public func push(_ route: ShopRoute) { shopPath.append(route) }
    public func push(_ route: ProfileRoute) { profilePath.append(route) }

    /// Pops the currently selected tab's stack to root.
    public func popToRoot(for tab: AppTab) {
        switch tab {
        case .home: homePath.removeAll()
        case .closet: closetPath.removeAll()
        case .studio: studioPath.removeAll()
        case .discover: discoverPath.removeAll()
        case .shop: shopPath.removeAll()
        case .profile: profilePath.removeAll()
        }
    }

    /// Selecting the already-active tab pops it to root, matching the
    /// standard iOS tab-bar convention.
    public func select(_ tab: AppTab) {
        if selectedTab == tab {
            popToRoot(for: tab)
        } else {
            selectedTab = tab
        }
    }

    public func presentModal(_ modal: AppModalRoute) {
        presentedModal = modal
    }

    public func dismissModal() {
        presentedModal = nil
    }

    /// Clears every per-tab stack and any presented modal.
    ///
    /// Call this on sign-out. Without it, the five path arrays outlive the
    /// session that produced them: sign out with the Closet tab three screens
    /// deep on an item detail, sign in as someone else, and the router would
    /// happily restore that stack — pointing at the previous account's item
    /// ids. The tab stacks are deliberately durable across tab switches
    /// (that is the Phase 1 exit criterion), which is exactly why they need an
    /// explicit tear-down at the one point where durability is wrong.
    public func resetForSignOut() {
        selectedTab = .home
        homePath.removeAll()
        closetPath.removeAll()
        studioPath.removeAll()
        discoverPath.removeAll()
        shopPath.removeAll()
        profilePath.removeAll()
        presentedModal = nil
    }

    // MARK: - Global actions (spec §4 "Global actions")

    public func startAskKyra(threadID: UUID? = nil) {
        presentModal(.askKyra(.thread(threadID: threadID)))
    }

    /// No gate in front of this any more. It used to check
    /// `blocksGuestScan` and divert to account creation, because a guest
    /// reaching the camera was a §22 dead button — effort spent capturing,
    /// then a refusal. Every session is now a real one (ADR 0014), so the
    /// only reader of that flag is gone and the scanner opens for everyone
    /// who can reach the button.
    public func startScan(mode: ScannerRoute = .singleItem) {
        presentModal(.scanner(mode))
    }

    public func startCreateOutfit() {
        presentModal(.outfitBuilder(.builder(startingOutfitID: nil)))
    }

    public func startAddOccasion() {
        presentModal(.addOccasion)
    }
}
