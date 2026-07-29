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
    case profile

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
        case .profile: "person.crop.circle"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .home: String(localized: "Home, Kyra's Daily Brief", comment: "VoiceOver label for the Home tab")
        case .closet: String(localized: "Closet", comment: "VoiceOver label for the Closet tab")
        case .studio: String(localized: "Style Studio", comment: "VoiceOver label for the Studio tab")
        case .discover: String(localized: "Discover", comment: "VoiceOver label for the Discover tab")
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
    case styleGuide(slug: String)
    case brandSpotlight(brand: String)
    case fitGuide(slug: String)
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
    case thread(threadID: UUID)
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

    public var id: String {
        switch self {
        case .scanner: "scanner"
        case .paywall: "paywall"
        case .outfitBuilder: "outfitBuilder"
        case .studioGeneration: "studioGeneration"
        case .askKyra: "askKyra"
        case .addOccasion: "addOccasion"
        }
    }
}

/// `@Observable` root router. Injected into the environment alongside
/// `AppContainer` and read by `RootView`, `MainTabView`, and every feature's
/// `Routing/` coordinator.
@MainActor
@Observable
public final class AppRouter {

    public var routeState: AppRouteState = .launching

    /// The currently selected tab. Persists across app relaunch via
    /// `AppStorage`-backed restoration performed by `MainTabView`.
    public var selectedTab: AppTab = .home

    // Independent navigation stacks — one per tab — so switching tabs never
    // discards where the user was (spec §4).
    public var homePath: [HomeRoute] = []
    public var closetPath: [ClosetRoute] = []
    public var studioPath: [StudioRoute] = []
    public var discoverPath: [DiscoverRoute] = []
    public var profilePath: [ProfileRoute] = []

    /// Active modal presentation, if any. Only one modal flow is presented
    /// at a time.
    public var presentedModal: AppModalRoute?

    public init() {}

    // MARK: - Convenience navigation

    public func push(_ route: HomeRoute) { homePath.append(route) }
    public func push(_ route: ClosetRoute) { closetPath.append(route) }
    public func push(_ route: StudioRoute) { studioPath.append(route) }
    public func push(_ route: DiscoverRoute) { discoverPath.append(route) }
    public func push(_ route: ProfileRoute) { profilePath.append(route) }

    /// Pops the currently selected tab's stack to root.
    public func popToRoot(for tab: AppTab) {
        switch tab {
        case .home: homePath.removeAll()
        case .closet: closetPath.removeAll()
        case .studio: studioPath.removeAll()
        case .discover: discoverPath.removeAll()
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

    // MARK: - Global actions (spec §4 "Global actions")

    public func startAskKyra(threadID: UUID? = nil) {
        presentModal(.askKyra(threadID.map(KyraRoute.thread) ?? .thread(threadID: UUID())))
    }

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
