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
    public let studioEstimateExporter: StudioEstimateExporting
    public let shoppingRepository: ShoppingRepository
    public let streakRepository: StreakRepository
    public let subscriptionRepository: SubscriptionRepository

    // MARK: - Platform services

    public let weatherService: WeatherService
    public let calendarService: CalendarService
    public let reminderService: ReminderService

    /// Camera session for the scanner modal (P3-SCAN-01). Protocol-typed so
    /// previews and unit tests inject `MockCaptureSessionController` without
    /// touching AVFoundation. Live adapter is constructed only here.
    public let captureSession: any CaptureSessionControlling

    /// In-memory drafts handed from capture to review (`ScannerRoute.review`
    /// carries only a UUID). Cleared when the modal dismisses.
    public let captureDraftStore: CaptureDraftStore
    /// Durable queue for JPEGs captured while offline, before analysis runs.
    public let pendingScanQueue: PendingScanQueue
    /// Write-ahead journal for scanner saves whose remote outcome is ambiguous.
    public let scannerSaveJournal: ScannerSaveJournaling
    public let scannerSaveRecoveryService: ScannerSaveRecoveryService

    // MARK: - Cross-cutting infrastructure

    public let apiClient: AstraAPIClient
    public let analyticsClient: AnalyticsClient
    public let offlineMutationQueue: OfflineMutationQueue
    public let offlineMutationDrainCoordinator: OfflineMutationDrainCoordinator?
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
        studioEstimateExporter: StudioEstimateExporting = LiveStudioEstimateExporter(),
        shoppingRepository: ShoppingRepository,
        streakRepository: StreakRepository,
        subscriptionRepository: SubscriptionRepository,
        weatherService: WeatherService,
        calendarService: CalendarService,
        reminderService: ReminderService,
        captureSession: any CaptureSessionControlling,
        captureDraftStore: CaptureDraftStore = CaptureDraftStore(),
        pendingScanQueue: PendingScanQueue,
        scannerSaveJournal: ScannerSaveJournaling = InMemoryScannerSaveJournal(),
        scannerSaveRecoveryService: ScannerSaveRecoveryService,
        apiClient: AstraAPIClient,
        analyticsClient: AnalyticsClient,
        offlineMutationQueue: OfflineMutationQueue,
        offlineMutationDrainCoordinator: OfflineMutationDrainCoordinator? = nil,
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
        self.studioEstimateExporter = studioEstimateExporter
        self.shoppingRepository = shoppingRepository
        self.streakRepository = streakRepository
        self.subscriptionRepository = subscriptionRepository
        self.weatherService = weatherService
        self.calendarService = calendarService
        self.reminderService = reminderService
        self.captureSession = captureSession
        self.captureDraftStore = captureDraftStore
        self.pendingScanQueue = pendingScanQueue
        self.scannerSaveJournal = scannerSaveJournal
        self.scannerSaveRecoveryService = scannerSaveRecoveryService
        self.apiClient = apiClient
        self.analyticsClient = analyticsClient
        self.offlineMutationQueue = offlineMutationQueue
        self.offlineMutationDrainCoordinator = offlineMutationDrainCoordinator
        self.networkMonitor = networkMonitor
        self.settings = settings
    }
}

// MARK: - Factories

extension AppContainer {

    private struct LiveClosetStack {
        let repository: ClosetRepository
        let remote: any ScannerSaveRemoteWriting
        let drainPendingMutations: @Sendable () async -> Void
    }

    private struct LiveContainerDependencies {
        let apiClient: AstraAPIClient
        let sessionStore: SessionStore
        let analyticsClient: AnalyticsClient
        let weatherService: WeatherService
        let calendarService: CalendarService
        let offlineMutationQueue: OfflineMutationQueue
        let pendingScanQueue: PendingScanQueue
        let scannerSaveJournal: ScannerSaveJournaling
        let scannerSaveRecoveryService: ScannerSaveRecoveryService
        let drainClosetMutations: @Sendable () async -> Void
        let subscriptionRepository: SubscriptionRepository
        let closetRepository: ClosetRepository
        let closetImageURLResolver: ClosetImageURLResolving
        let modelContainer: ModelContainer
        let networkMonitor: NetworkReachabilityMonitoring
    }

    private struct PreviewContainerDependencies {
        let sessionStore: SessionStore
        let referenceBody: BodyProfile
        let chatPreviewID: UUID?
        let studioRepository: MockStudioRepository
        let closetRepository: ClosetRepository
        let closetImageURLResolver: ClosetImageURLResolving
        let outfitRepository: OutfitRepository
        let subscriptionRepository: SubscriptionRepository
        let scannerSaveJournal: ScannerSaveJournaling
        let scannerSaveRecoveryService: ScannerSaveRecoveryService
    }

    /// Production dependency graph. Talks to Supabase Edge Functions per
    /// spec §8; the client never talks to a model provider directly.
    public static func live() throws -> AppContainer {
        // Open durable storage before constructing repositories, queues, or
        // services. If this fails, the app remains in its startup recovery
        // screen and no write path can target an ephemeral substitute.
        let modelContainer = try AstraModelContainer.live()
        let environment = AstraEnvironment.current
        let apiClient = AstraAPIClient(environment: environment)
        let sessionStore = SessionStore(apiClient: apiClient)
        let analyticsClient = LiveAnalyticsClient()
        let weatherService = LiveWeatherService()
        let calendarService = LiveCalendarService()

        let offlineMutationQueue = SwiftDataOfflineMutationQueue(modelContainer: modelContainer)
        let pendingScanQueue = SwiftDataPendingScanQueue(modelContainer: modelContainer)
        let scannerSaveJournal = SwiftDataScannerSaveJournal(modelContainer: modelContainer)
        let networkMonitor = SystemNetworkReachabilityMonitor()
        let subscriptionRepository = LiveSubscriptionRepository(apiClient: apiClient)
        let closetStack = makeLiveClosetStack(
            apiClient: apiClient,
            offlineMutationQueue: offlineMutationQueue,
            modelContainer: modelContainer,
            subscriptionRepository: subscriptionRepository,
            sessionStore: sessionStore
        )
        let scannerSaveRecoveryService = makeScannerSaveRecoveryService(
            journal: scannerSaveJournal,
            repository: closetStack.repository,
            remote: closetStack.remote,
            sessionStore: sessionStore,
            offlineMutationQueue: offlineMutationQueue
        )

        return makeLiveContainer(LiveContainerDependencies(
            apiClient: apiClient,
            sessionStore: sessionStore,
            analyticsClient: analyticsClient,
            weatherService: weatherService,
            calendarService: calendarService,
            offlineMutationQueue: offlineMutationQueue,
            pendingScanQueue: pendingScanQueue,
            scannerSaveJournal: scannerSaveJournal,
            scannerSaveRecoveryService: scannerSaveRecoveryService,
            drainClosetMutations: closetStack.drainPendingMutations,
            subscriptionRepository: subscriptionRepository,
            closetRepository: closetStack.repository,
            closetImageURLResolver: LiveClosetImageURLResolver(apiClient: apiClient),
            modelContainer: modelContainer,
            networkMonitor: networkMonitor
        ))
    }

    private static func makeLiveContainer(_ dependencies: LiveContainerDependencies) -> AppContainer {
        let sessionStore = dependencies.sessionStore
        let drainClosetMutations = dependencies.drainClosetMutations
        let outfitRepository = LiveOutfitRepository(
            apiClient: dependencies.apiClient,
            offlineQueue: dependencies.offlineMutationQueue,
            cache: SwiftDataOutfitCache(modelContainer: dependencies.modelContainer)
        )
        let profileRepository = LiveProfileRepository(
            apiClient: dependencies.apiClient,
            profileCache: SwiftDataProfileSnapshotCache(modelContainer: dependencies.modelContainer),
            offlineQueue: dependencies.offlineMutationQueue,
            currentUserID: { await sessionStore.currentUserID() }
        )
        let offlineMutationDrainCoordinator = OfflineMutationDrainCoordinator(
            currentOwnerID: { await sessionStore.currentUserID() },
            drainCloset: drainClosetMutations,
            drainOutfits: { await outfitRepository.drainPendingMutations() },
            drainProfiles: { await profileRepository.drainPendingMutations() }
        )
        return AppContainer(
            sessionStore: dependencies.sessionStore,
            authRepository: LiveAuthRepository(apiClient: dependencies.apiClient, sessionStore: dependencies.sessionStore),
            profileRepository: profileRepository,
            closetRepository: dependencies.closetRepository,
            closetImageURLResolver: dependencies.closetImageURLResolver,
            outfitRepository: outfitRepository,
            kyraRepository: LiveKyraRepository(
                apiClient: dependencies.apiClient,
                weatherService: dependencies.weatherService,
                calendarService: dependencies.calendarService
            ),
            studioRepository: LiveStudioRepository(apiClient: dependencies.apiClient),
            shoppingRepository: LiveShoppingRepository(apiClient: dependencies.apiClient),
            streakRepository: LiveStreakRepository(),
            subscriptionRepository: dependencies.subscriptionRepository,
            weatherService: dependencies.weatherService,
            calendarService: dependencies.calendarService,
            reminderService: LiveReminderService(),
            captureSession: LiveCaptureSessionController(),
            pendingScanQueue: dependencies.pendingScanQueue,
            scannerSaveJournal: dependencies.scannerSaveJournal,
            scannerSaveRecoveryService: dependencies.scannerSaveRecoveryService,
            apiClient: dependencies.apiClient,
            analyticsClient: dependencies.analyticsClient,
            offlineMutationQueue: dependencies.offlineMutationQueue,
            offlineMutationDrainCoordinator: offlineMutationDrainCoordinator,
            networkMonitor: dependencies.networkMonitor,
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
        subscriptionRepository: SubscriptionRepository,
        sessionStore: SessionStore
    ) -> LiveClosetStack {
        let liveClosetRepository = LiveClosetRepository(
            apiClient: apiClient,
            offlineQueue: offlineMutationQueue,
            cache: SwiftDataClosetItemCache(modelContainer: modelContainer)
        )
        let freeTierCappedClosetRepository = FreeTierCappedClosetRepository(
            base: liveClosetRepository,
            isEntitledToPremium: {
                do {
                    return try await subscriptionRepository.fetchCurrentSubscription().isEntitledToPremium
                } catch {
                    return false
                }
            },
            isAnonymous: {
                await sessionStore.currentIsAnonymous()
            }
        )
        return LiveClosetStack(
            repository: freeTierCappedClosetRepository,
            remote: liveClosetRepository,
            drainPendingMutations: { await liveClosetRepository.drainPendingMutations() }
        )
    }

    private static func offlineQueueContainsCreate(
        _ queue: OfflineMutationQueue,
        ownerID: UUID,
        itemID: UUID
    ) async -> Bool {
        for mutation in await queue.pendingMutations() where mutation.entity == .closetItem && mutation.operation == .create {
            if let payload = try? JSONDecoder.astraDefault.decode(ClosetCreateMutationPayload.self, from: mutation.payloadData),
               payload.item.id == itemID, payload.item.userID == ownerID {
                return true
            }
            if let item = try? JSONDecoder.astraDefault.decode(ClosetItem.self, from: mutation.payloadData),
               item.id == itemID, item.userID == ownerID {
                return true
            }
        }
        return false
    }

    private static func makeScannerSaveRecoveryService(
        journal: ScannerSaveJournaling,
        repository: ClosetRepository,
        remote: any ScannerSaveRemoteWriting,
        sessionStore: SessionStore,
        offlineMutationQueue: OfflineMutationQueue? = nil
    ) -> ScannerSaveRecoveryService {
        ScannerSaveRecoveryService(
            journal: journal,
            repository: repository,
            remote: remote,
            currentUserID: { await sessionStore.currentUserID() },
            hasDurableQueuedCreate: { ownerID, itemID in
                guard let offlineMutationQueue else { return false }
                return await Self.offlineQueueContainsCreate(offlineMutationQueue, ownerID: ownerID, itemID: itemID)
            }
        )
    }

    /// Preview / early-UI dependency graph. Every dependency is an
    /// in-memory mock from `Core/Mocks`, seeded with believable sample data
    /// so SwiftUI previews render without a backend (spec §31).
    public static func preview(outfitRepository: (any OutfitRepository)? = nil) -> AppContainer {
        // Explicitly pass the preview Supabase client rather than relying
        // on `SessionStore`'s default parameter, which otherwise evaluates
        // `AstraEnvironment.current` and will `preconditionFailure` in a
        // preview/test process that has no configured Info.plist secrets.
        let sessionStore = SessionStore(apiClient: .previewClient, supabase: AstraSupabaseClientFactory.previewClient)

        let mockClosetRepository = MockClosetRepository(
            items: AstraFeatureFlags.usesPerformanceClosetFixture
                ? PerformanceClosetFixture.items
                : SampleData.closetItems
        )
        var referenceBody = SampleData.bodyProfile
        let referencePath = ProcessInfo.processInfo.arguments.contains("-astra-test-reference-photo")
            ? "users/\(SampleData.userID.uuidString.lowercased())/references/\(UUID().uuidString.lowercased()).jpg" : nil
        if let referencePath { referenceBody.appearance.referenceSelfiePaths = [referencePath] }
        let chatPreviewID = ProcessInfo.processInfo.arguments.contains("-astra-test-chat-preview") ? UUID() : nil
        let mockStudioRepository = MockStudioRepository(
            pendingImageDeletionCount: ProcessInfo.processInfo.arguments.contains("-astra-test-pending-image-removal") ? 1 : 0,
            referencePhotoPath: referencePath, chatPreviewID: chatPreviewID
        )
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
        let scannerSaveJournal = InMemoryScannerSaveJournal()
        let scannerSaveRecoveryService = makeScannerSaveRecoveryService(
            journal: scannerSaveJournal,
            repository: freeTierCappedClosetRepository,
            remote: mockClosetRepository,
            sessionStore: sessionStore
        )
        return makePreviewContainer(PreviewContainerDependencies(
            sessionStore: sessionStore,
            referenceBody: referenceBody,
            chatPreviewID: chatPreviewID,
            studioRepository: mockStudioRepository,
            closetRepository: freeTierCappedClosetRepository,
            closetImageURLResolver: AstraFeatureFlags.usesPerformanceClosetFixture
                ? PerformanceClosetImageURLResolver()
                : MockClosetImageURLResolver(),
            outfitRepository: outfitRepository ?? MockOutfitRepository(),
            subscriptionRepository: subscriptionRepository,
            scannerSaveJournal: scannerSaveJournal,
            scannerSaveRecoveryService: scannerSaveRecoveryService
        ))
    }

    private static func makePreviewContainer(_ dependencies: PreviewContainerDependencies) -> AppContainer {
        AppContainer(
            sessionStore: dependencies.sessionStore,
            authRepository: MockAuthRepository(sessionStore: dependencies.sessionStore),
            profileRepository: MockProfileRepository(bodyProfile: dependencies.referenceBody, studioRepository: dependencies.studioRepository),
            closetRepository: dependencies.closetRepository,
            closetImageURLResolver: dependencies.closetImageURLResolver,
            outfitRepository: dependencies.outfitRepository,
            kyraRepository: MockKyraRepository(previewGenerationID: dependencies.chatPreviewID),
            studioRepository: dependencies.studioRepository,
            studioEstimateExporter: MockStudioEstimateExporter(),
            shoppingRepository: MockShoppingRepository(),
            streakRepository: MockStreakRepository(),
            subscriptionRepository: dependencies.subscriptionRepository,
            weatherService: MockWeatherService(),
            calendarService: MockCalendarService(),
            reminderService: MockReminderService(),
            captureSession: MockCaptureSessionController(isHardwareAvailable: false),
            captureDraftStore: CaptureDraftStore(),
            pendingScanQueue: InMemoryPendingScanQueue(),
            scannerSaveJournal: dependencies.scannerSaveJournal,
            scannerSaveRecoveryService: dependencies.scannerSaveRecoveryService,
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
