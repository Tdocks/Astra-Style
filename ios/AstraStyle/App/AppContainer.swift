//
//  AppContainer.swift
//  AstraStyle
//
//  Protocol-based dependency injection root (spec §8 "Dependency approach").
//  No third-party DI framework: `AppContainer` is a plain `@Observable`
//  object that owns every repository/service protocol the app needs and
//  exposes two factories:
//
//    - `AppContainer.live()`    wires production implementations (Supabase
//      networking, SwiftData persistence, StoreKit, Keychain, etc).
//    - `AppContainer.preview()` wires the in-memory mocks from
//      `Core/Mocks` so SwiftUI previews and early UI work never touch the
//      network.
//
//  Views never construct dependencies themselves; they read `AppContainer`
//  from the SwiftUI environment and receive already-configured view models.
//

import Foundation
import Observation
import Supabase

/// The single dependency-injection root for Astra Style.
///
/// `AppContainer` is intentionally a flat bag of protocol-typed properties
/// rather than a graph of nested containers. Every feature module depends
/// only on the protocols declared in `Domain/Repositories` and
/// `Domain/Services`; nothing in `Features/` imports a concrete
/// implementation type directly.
@MainActor
@Observable
public final class AppContainer {

    // MARK: - Session / Auth

    public let sessionStore: SessionStore

    // MARK: - Repositories (Domain/Repositories protocols)

    public let authRepository: AuthRepository

    /// Owns the four profile tables plus the two orchestration calls
    /// onboarding depends on — `POST /profile/complete-onboarding` and
    /// `POST /style-dna/generate` (spec §14).
    ///
    /// NOTE ON SPEC §8's FIVE PROVIDER PROTOCOLS. `StylistReasoningProvider`,
    /// `VisionAnalysisProvider`, `ImageGenerationProvider`,
    /// `EmbeddingProvider` and `ProductExtractionProvider` are deliberately
    /// absent from this container and from `ios/` entirely. They are
    /// SERVER-side protocols — `StylistReasoningProvider` lives in
    /// `supabase/functions/_shared/providers/stylistReasoning.ts` — and ADR
    /// 0004's decision 3 is explicit that the client never holds a provider
    /// key and never constructs a request to a model vendor. A Swift
    /// counterpart would be a dependency-injection seam for something the app
    /// is structurally forbidden from doing, and its existence would invite
    /// exactly the shortcut the ADR exists to prevent.
    ///
    /// The client's seam for every AI-backed capability is the repository
    /// protocol in front of the Edge Function that calls the provider —
    /// `profileRepository` for Style DNA, `kyraRepository` for Kyra,
    /// `studioRepository` for Style Studio. Swapping the vendor behind any of
    /// them is a server-side change with no app release.
    public let profileRepository: ProfileRepository
    public let closetRepository: ClosetRepository
    public let outfitRepository: OutfitRepository
    public let kyraRepository: KyraRepository
    public let studioRepository: StudioRepository
    public let shoppingRepository: ShoppingRepository
    public let subscriptionRepository: SubscriptionRepository

    // MARK: - Guest mode (spec §6.2; ADR 0011)

    /// Transfers a guest's local closet items to a newly-authenticated
    /// account. `closetRepository` above already routes guest calls to
    /// local-only storage; this is the separate, explicit step that moves
    /// that local data onto the real account once one exists.
    public let guestMigrationService: GuestMigrationService

    // MARK: - Platform services

    public let weatherService: WeatherService
    public let calendarService: CalendarService

    // MARK: - Cross-cutting infrastructure

    public let apiClient: AstraAPIClient
    public let analyticsClient: AnalyticsClient
    public let offlineMutationQueue: OfflineMutationQueue
    public let settings: AppSettings

    public init(
        sessionStore: SessionStore,
        authRepository: AuthRepository,
        profileRepository: ProfileRepository,
        closetRepository: ClosetRepository,
        outfitRepository: OutfitRepository,
        kyraRepository: KyraRepository,
        studioRepository: StudioRepository,
        shoppingRepository: ShoppingRepository,
        subscriptionRepository: SubscriptionRepository,
        guestMigrationService: GuestMigrationService,
        weatherService: WeatherService,
        calendarService: CalendarService,
        apiClient: AstraAPIClient,
        analyticsClient: AnalyticsClient,
        offlineMutationQueue: OfflineMutationQueue,
        settings: AppSettings
    ) {
        self.sessionStore = sessionStore
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.closetRepository = closetRepository
        self.outfitRepository = outfitRepository
        self.kyraRepository = kyraRepository
        self.studioRepository = studioRepository
        self.shoppingRepository = shoppingRepository
        self.subscriptionRepository = subscriptionRepository
        self.guestMigrationService = guestMigrationService
        self.weatherService = weatherService
        self.calendarService = calendarService
        self.apiClient = apiClient
        self.analyticsClient = analyticsClient
        self.offlineMutationQueue = offlineMutationQueue
        self.settings = settings
    }
}

// MARK: - Factories

extension AppContainer {

    /// Production dependency graph. Talks to Supabase Edge Functions per
    /// spec §8; the client never talks to a model provider directly.
    public static func live() -> AppContainer {
        let environment = AstraEnvironment.current
        let apiClient = AstraAPIClient(environment: environment)
        let sessionStore = SessionStore(apiClient: apiClient)
        let analyticsClient = LiveAnalyticsClient()

        // Fall back to an in-memory store if the on-disk container fails
        // to initialize (e.g. an unreadable/corrupt store) rather than
        // crashing at launch — offline caching degrades to "no caching
        // this session" instead of bricking the app.
        let modelContainer = (try? AstraModelContainer.live()) ?? AstraModelContainer.preview()
        let offlineMutationQueue = SwiftDataOfflineMutationQueue(modelContainer: modelContainer)

        // Guest mode (spec §6.2; ADR 0011): `liveClosetRepository` is kept
        // as its own reference — not just reachable through
        // `guestAwareClosetRepository` below — because migration must
        // always write through the real, network-backed repository even
        // while the session mid-migration is still technically a guest.
        let guestClosetStore = SwiftDataGuestClosetStore(modelContainer: modelContainer)
        let liveClosetRepository = LiveClosetRepository(apiClient: apiClient, offlineQueue: offlineMutationQueue)
        let guestClosetRepository = GuestClosetRepository(
            store: guestClosetStore,
            currentGuestUserID: { await sessionStore.currentGuestUserID() }
        )
        let guestAwareClosetRepository = GuestAwareClosetRepository(
            isGuest: { await sessionStore.currentIsGuest() },
            guestRepository: guestClosetRepository,
            liveRepository: liveClosetRepository
        )
        let guestMigrationService = LiveGuestMigrationService(
            closetRepository: liveClosetRepository,
            guestClosetStore: guestClosetStore
        )

        return AppContainer(
            sessionStore: sessionStore,
            authRepository: LiveAuthRepository(apiClient: apiClient, sessionStore: sessionStore),
            profileRepository: LiveProfileRepository(apiClient: apiClient),
            closetRepository: guestAwareClosetRepository,
            outfitRepository: LiveOutfitRepository(apiClient: apiClient, offlineQueue: offlineMutationQueue),
            kyraRepository: LiveKyraRepository(apiClient: apiClient),
            studioRepository: LiveStudioRepository(apiClient: apiClient),
            shoppingRepository: LiveShoppingRepository(apiClient: apiClient),
            subscriptionRepository: LiveSubscriptionRepository(apiClient: apiClient),
            guestMigrationService: guestMigrationService,
            weatherService: LiveWeatherService(),
            calendarService: LiveCalendarService(),
            apiClient: apiClient,
            analyticsClient: analyticsClient,
            offlineMutationQueue: offlineMutationQueue,
            settings: AppSettings()
        )
    }

    /// Preview / early-UI dependency graph. Every dependency is an
    /// in-memory mock from `Core/Mocks`, seeded with believable sample data
    /// so SwiftUI previews render without a backend (spec §31).
    public static func preview() -> AppContainer {
        // Explicitly pass the preview Supabase client rather than relying
        // on `SessionStore`'s default parameter, which otherwise evaluates
        // `AstraEnvironment.current` and will `preconditionFailure` in a
        // preview/test process that has no configured Info.plist secrets.
        let sessionStore = SessionStore(apiClient: .previewClient, supabase: AstraSupabaseClientFactory.previewClient)

        let mockClosetRepository = MockClosetRepository()
        let guestClosetStore = InMemoryGuestClosetStore()
        let guestClosetRepository = GuestClosetRepository(
            store: guestClosetStore,
            currentGuestUserID: { await sessionStore.currentGuestUserID() }
        )
        let guestAwareClosetRepository = GuestAwareClosetRepository(
            isGuest: { await sessionStore.currentIsGuest() },
            guestRepository: guestClosetRepository,
            liveRepository: mockClosetRepository
        )
        let guestMigrationService = LiveGuestMigrationService(
            closetRepository: mockClosetRepository,
            guestClosetStore: guestClosetStore
        )

        return AppContainer(
            sessionStore: sessionStore,
            authRepository: MockAuthRepository(sessionStore: sessionStore),
            profileRepository: MockProfileRepository(),
            closetRepository: guestAwareClosetRepository,
            outfitRepository: MockOutfitRepository(),
            kyraRepository: MockKyraRepository(),
            studioRepository: MockStudioRepository(),
            shoppingRepository: MockShoppingRepository(),
            subscriptionRepository: MockSubscriptionRepository(),
            guestMigrationService: guestMigrationService,
            weatherService: MockWeatherService(),
            calendarService: MockCalendarService(),
            apiClient: .previewClient,
            analyticsClient: NoOpAnalyticsClient(),
            offlineMutationQueue: InMemoryOfflineMutationQueue(),
            settings: AppSettings()
        )
    }
}

/// Lightweight, persisted user-facing app settings that are not part of the
/// authenticated domain model (e.g. color scheme override).
///
/// Reuses `Domain/Models/Enums.swift`'s `ThemePreference` (the same type
/// `profiles.theme` maps to) rather than declaring a parallel App-layer
/// enum — `App` is allowed to depend on `Domain`, so there's no reason for
/// two identical `system/light/dark` types to exist. Astra Style defaults
/// to dark mode per the brand's "black marble" visual direction (spec §3)
/// but always allows a user override, never a hardcoded lock, to respect
/// system accessibility settings.
@MainActor
@Observable
public final class AppSettings {
    public var preferredColorScheme: ThemePreference

    public init(preferredColorScheme: ThemePreference = .dark) {
        self.preferredColorScheme = preferredColorScheme
    }
}
