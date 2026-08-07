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
import SwiftData

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

    /// Signs `user-content` storage paths so closet surfaces can display
    /// photos (spec §15's private bucket).
    ///
    /// Its own dependency rather than a method on `ClosetRepository`
    /// because it is not a repository: it owns no table, performs no
    /// mutation, and its whole behaviour is a caching policy over Storage.
    public let closetImageURLResolver: ClosetImageURLResolving

    public let outfitRepository: OutfitRepository
    public let kyraRepository: KyraRepository
    public let studioRepository: StudioRepository
    public let shoppingRepository: ShoppingRepository
    public let subscriptionRepository: SubscriptionRepository

    // MARK: - Platform services

    public let weatherService: WeatherService
    public let calendarService: CalendarService

    /// Camera session for the scanner modal (P3-SCAN-01). Protocol-typed so
    /// previews and unit tests inject `MockCaptureSessionController` without
    /// touching AVFoundation. Live adapter is constructed only here.
    public let captureSession: any CaptureSessionControlling

    /// In-memory drafts handed from capture to review (`ScannerRoute.review`
    /// carries only a UUID). Cleared when the modal dismisses.
    public let captureDraftStore: CaptureDraftStore
    /// Durable queue for JPEGs captured while offline, before analysis runs.
    public let pendingScanQueue: PendingScanQueue

    // MARK: - Cross-cutting infrastructure

    public let apiClient: AstraAPIClient
    public let analyticsClient: AnalyticsClient
    public let offlineMutationQueue: OfflineMutationQueue
    public let networkMonitor: NetworkReachabilityMonitoring
    public let settings: AppSettings

    public init(
        sessionStore: SessionStore,
        authRepository: AuthRepository,
        profileRepository: ProfileRepository,
        closetRepository: ClosetRepository,
        closetImageURLResolver: ClosetImageURLResolving,
        outfitRepository: OutfitRepository,
        kyraRepository: KyraRepository,
        studioRepository: StudioRepository,
        shoppingRepository: ShoppingRepository,
        subscriptionRepository: SubscriptionRepository,
        weatherService: WeatherService,
        calendarService: CalendarService,
        captureSession: any CaptureSessionControlling,
        captureDraftStore: CaptureDraftStore = CaptureDraftStore(),
        pendingScanQueue: PendingScanQueue,
        apiClient: AstraAPIClient,
        analyticsClient: AnalyticsClient,
        offlineMutationQueue: OfflineMutationQueue,
        networkMonitor: NetworkReachabilityMonitoring,
        settings: AppSettings
    ) {
        self.sessionStore = sessionStore
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.closetRepository = closetRepository
        self.closetImageURLResolver = closetImageURLResolver
        self.outfitRepository = outfitRepository
        self.kyraRepository = kyraRepository
        self.studioRepository = studioRepository
        self.shoppingRepository = shoppingRepository
        self.subscriptionRepository = subscriptionRepository
        self.weatherService = weatherService
        self.calendarService = calendarService
        self.captureSession = captureSession
        self.captureDraftStore = captureDraftStore
        self.pendingScanQueue = pendingScanQueue
        self.apiClient = apiClient
        self.analyticsClient = analyticsClient
        self.offlineMutationQueue = offlineMutationQueue
        self.networkMonitor = networkMonitor
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
        let pendingScanQueue = SwiftDataPendingScanQueue(modelContainer: modelContainer)
        let networkMonitor = SystemNetworkReachabilityMonitor()
        let subscriptionRepository = LiveSubscriptionRepository(apiClient: apiClient)
        let closetRepository = makeLiveClosetStack(
            apiClient: apiClient,
            offlineMutationQueue: offlineMutationQueue,
            modelContainer: modelContainer,
            subscriptionRepository: subscriptionRepository
        )

        return AppContainer(
            sessionStore: sessionStore,
            authRepository: LiveAuthRepository(apiClient: apiClient, sessionStore: sessionStore),
            profileRepository: LiveProfileRepository(apiClient: apiClient),
            closetRepository: closetRepository,
            closetImageURLResolver: LiveClosetImageURLResolver(),
            outfitRepository: LiveOutfitRepository(
                apiClient: apiClient,
                offlineQueue: offlineMutationQueue,
                cache: SwiftDataOutfitCache(modelContainer: modelContainer)
            ),
            kyraRepository: LiveKyraRepository(apiClient: apiClient),
            studioRepository: LiveStudioRepository(apiClient: apiClient),
            shoppingRepository: LiveShoppingRepository(apiClient: apiClient),
            subscriptionRepository: subscriptionRepository,
            weatherService: LiveWeatherService(),
            calendarService: LiveCalendarService(),
            captureSession: LiveCaptureSessionController(),
            pendingScanQueue: pendingScanQueue,
            apiClient: apiClient,
            analyticsClient: analyticsClient,
            offlineMutationQueue: offlineMutationQueue,
            networkMonitor: networkMonitor,
            settings: AppSettings()
        )
    }

    /// The live closet stack: Postgres-backed CRUD behind spec §16's
    /// free-tier 30-item cap.
    ///
    /// One wrapper, not two. `GuestAwareClosetRepository` used to sit on
    /// top of this and route each call to local storage or to Supabase
    /// depending on the session; ADR 0014 removed guest mode, so every
    /// closet call now goes to one place and no call site has to ask which.
    private static func makeLiveClosetStack(
        apiClient: AstraAPIClient,
        offlineMutationQueue: OfflineMutationQueue,
        modelContainer: ModelContainer,
        subscriptionRepository: SubscriptionRepository
    ) -> ClosetRepository {
        let liveClosetRepository = LiveClosetRepository(
            apiClient: apiClient,
            offlineQueue: offlineMutationQueue,
            cache: SwiftDataClosetItemCache(modelContainer: modelContainer)
        )
        let freeTierCappedClosetRepository = FreeTierCappedClosetRepository(
            base: liveClosetRepository,
            isEntitledToPremium: {
                // Fail closed to free-tier limits when subscription lookup
                // errors — uncapping on a network blip would let a free
                // account past 30 until the next launch.
                do {
                    return try await subscriptionRepository.fetchCurrentSubscription().isEntitledToPremium
                } catch {
                    return false
                }
            }
        )
        return freeTierCappedClosetRepository
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
        // Preview / `-astra-mock-backend` seeds an active Premium
        // subscription so closet UI tests are not blocked by the free
        // 30-item cap while exercising add flows against SampleData's
        // ~25-item wardrobe. Free-tier enforcement is covered by unit
        // tests with an explicit non-entitled fixture.
        let subscriptionRepository = MockSubscriptionRepository(status: .active)
        let freeTierCappedClosetRepository = FreeTierCappedClosetRepository(
            base: mockClosetRepository,
            isEntitledToPremium: {
                (try? await subscriptionRepository.fetchCurrentSubscription())?.isEntitledToPremium ?? false
            }
        )
        return AppContainer(
            sessionStore: sessionStore,
            authRepository: MockAuthRepository(sessionStore: sessionStore),
            profileRepository: MockProfileRepository(),
            closetRepository: freeTierCappedClosetRepository,
            closetImageURLResolver: MockClosetImageURLResolver(),
            outfitRepository: MockOutfitRepository(),
            kyraRepository: MockKyraRepository(),
            studioRepository: MockStudioRepository(),
            shoppingRepository: MockShoppingRepository(),
            subscriptionRepository: subscriptionRepository,
            weatherService: MockWeatherService(),
            calendarService: MockCalendarService(),
            captureSession: MockCaptureSessionController(isHardwareAvailable: false),
            captureDraftStore: CaptureDraftStore(),
            pendingScanQueue: InMemoryPendingScanQueue(),
            apiClient: .previewClient,
            analyticsClient: NoOpAnalyticsClient(),
            offlineMutationQueue: InMemoryOfflineMutationQueue(),
            networkMonitor: StaticNetworkReachabilityMonitor(offline: false),
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
