//
//  AstraStyleApp.swift
//  AstraStyle
//
//  App entry point. Matches spec §27 "Sample Root App Structure" exactly:
//  a single `AppContainer` is created once, injected into the environment,
//  and `RootView` switches on `AppRouter.routeState`.
//

import SwiftUI
import Observation

@main
struct AstraStyleApp: App {
    // `preview()` under `-astra-mock-backend` (Debug only — see
    // AstraFeatureFlags). Selected here rather than inside `live()` so there is
    // exactly one place that decides which dependency graph the process runs
    // on, and it is visible at the entry point rather than buried in a factory.
    @State private var startupController = AppStartupController()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            Group {
                switch startupController.state {
                case .opening:
                    ProgressView("Opening saved data…")
                        .tint(AstraColor.accentChampagne)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
                case .failed:
                    PersistentStoreRecoveryView {
                        startupController.retry()
                    }
                case .ready(let appContainer):
                    RootView()
                        .environment(appContainer)
                        .environment(router)
                        .environment(appContainer.sessionStore)
                        .preferredColorScheme((AstraFeatureFlags.forcedTheme ?? appContainer.settings.preferredColorScheme).resolvedColorScheme)
                        .task {
                            await bootstrap(using: appContainer)
                        }
                        .task {
                            await observeConnectivityForScannerRecovery(using: appContainer)
                        }
                        .onChange(of: appContainer.sessionStore.currentSession?.userID) { _, ownerID in
                            guard let ownerID else { return }
                            let recovery = appContainer.scannerSaveRecoveryService
                            let mutationDrain = appContainer.offlineMutationDrainCoordinator
                            Task {
                                await recovery.recover(ownerID: ownerID)
                                await mutationDrain?.sessionChanged(ownerID: ownerID)
                            }
                        }
                }
            }
            .preferredColorScheme(AstraFeatureFlags.forcedTheme?.resolvedColorScheme)
            .task { startupController.openIfNeeded() }
        }
    }

    /// Restores the session, then advances `AppRouter.routeState` out of
    /// `.launching`. Kept out of `RootView` so the view stays a pure
    /// function of state (no network calls in views, spec §8).
    /// Spec §6.1: the splash shows for "1.4-second maximum before routing".
    ///
    /// That is a hard ceiling on how long a user stares at a logo, and nothing
    /// previously enforced it. `bootstrap()` awaited a profile fetch on every
    /// launch with no time bound at all, so a slow or hanging network trapped
    /// the user on the splash indefinitely — the exact failure the spec's
    /// maximum exists to prevent.
    private static let splashDeadline: Duration = .milliseconds(1400)

    /// A launch faster than this reads as a flicker rather than as speed, so
    /// the brand moment gets a floor. Well under the ceiling above.
    private static let splashMinimumDwell: Duration = .milliseconds(450)

    /// Restores the session, then advances `AppRouter.routeState` out of
    /// `.launching`. Kept out of `RootView` so the view stays a pure
    /// function of state (no network calls in views, spec §8).
    private func bootstrap(using appContainer: AppContainer) async {
        let route = await withMinimumDuration(Self.splashMinimumDwell) {
            await self.resolveLaunchRoute(using: appContainer)
        }
        router.routeState = route
    }

    private func resolveLaunchRoute(using appContainer: AppContainer) async -> AppRouteState {
        if AstraFeatureFlags.resetsStateOnLaunch {
            // Test-only reset is local. Calling Supabase Auth's sign-out here
            // would add a network dependency to UI tests and fail offline.
            appContainer.sessionStore.resetForUITest()
        }

        if AstraFeatureFlags.usesMockBackend {
            // A fresh in-memory identity scopes mock writes to this process
            // and cannot pollute the real Keychain session.
            appContainer.sessionStore.adoptInMemory(
                AuthSession(
                    userID: UUID(),
                    accessToken: "mock-backend",
                    refreshToken: "mock-backend",
                    expiresAt: .now.addingTimeInterval(3600)
                )
            )
            // Respect `-astra-skip-onboarding` the same way Apple and email
            // auth do via `AppRouter.postAuthenticationRoute`, so UI
            // tests can reach the Closet tab against mocks without walking
            // §6.3–§6.10 first (P3-TEST-02).
            return AppRouter.postAuthenticationRoute
        }

        if AstraFeatureFlags.resetsStateOnLaunch {
            return .signedOut
        }

        // Reading the Keychain is instant; `restoreSession()` only touches the
        // network when the stored token has actually expired. Bounded anyway,
        // because "only sometimes hangs" is still hangs.
        let restored = await withDeadline(Self.splashDeadline) {
            try await appContainer.sessionStore.restoreSession()
        }

        // Whether a session came back, not what was in it. Removing guest mode
        // removed the only reader of the session itself — the guest branch
        // below asked it whether it was one — and a bound value nobody reads
        // is a warning, which the CI warning gate treats as a failure.
        // `sessionStore` holds the credentials the profile fetch needs.
        //
        // Still a switch rather than `if case .success`: a future
        // `RestoreOutcome` case should have to be classified here, not fall
        // through to whichever branch happens to be the default.
        let hasSession: Bool
        switch restored {
        case .success(let value):
            hasSession = value != nil
        case .timedOut, .failed:
            hasSession = false
        }

        guard hasSession else {
            // No stored session, or restoring it failed or timed out. All
            // resolve to Welcome: without credentials there is nothing else to
            // show.
            return .signedOut
        }

        // Every restored session has a server-side profile row to ask about
        // (ADR 0014), so there is no branch here any more — the guest case
        // returned `.main` without fetching anything, because a guest had no
        // row and an empty access token.
        let profileOutcome = await withDeadline(Self.splashDeadline) {
            try await appContainer.profileRepository.fetchCurrentProfile()
        }

        switch profileOutcome {
        case .success(let profile):
            return profile.onboardingCompletedAt != nil ? .main : .onboarding

        case .timedOut:
            // We hold real credentials; the network was just slow. Sending an
            // authenticated user back to Welcome would make them sign in again
            // to reach the same place. Let them in — Home has its own loading
            // and offline states.
            return .main

        case .failed(let error):
            // A rejected session is NOT a slow one. If the server says the
            // credentials are no good, dropping the user on Home leaves them
            // staring at "Couldn't load your profile" with no route back to
            // sign-in — a dead end, and one this QA sweep actually caught.
            // Clear the bad session and send them somewhere they can act.
            if (error as? AstraError)?.category == .auth {
                try? await appContainer.sessionStore.signOut()
                return .signedOut
            }
            // Any other failure (5xx, offline, decode) is plausibly transient,
            // so keep the session and let Home offer a retry.
            return .main
        }
    }

    private func observeConnectivityForScannerRecovery(using appContainer: AppContainer) async {
        let mutationDrain = appContainer.offlineMutationDrainCoordinator
        await mutationDrain?.connectivityChanged(
            isOnline: !(await appContainer.networkMonitor.isOffline())
        )
        for await isOnline in appContainer.networkMonitor.connectivityUpdates() {
            await mutationDrain?.connectivityChanged(isOnline: isOnline)
            guard isOnline else { continue }
            guard let ownerID = await appContainer.sessionStore.currentUserID() else { continue }
            await appContainer.scannerSaveRecoveryService.recover(ownerID: ownerID)
        }
    }
}

extension ThemePreference {
    /// Bridges the domain's `profiles.theme` preference to SwiftUI's
    /// `ColorScheme?`, where `nil` means "follow the system setting".
    var resolvedColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
@Observable
final class AppStartupController {
    enum State {
        case opening
        case failed
        case ready(AppContainer)
    }

    private(set) var state: State = .opening
    private var didAttemptOpen = false
    private let containerFactory: (() throws -> AppContainer)?
    private var shouldFailInitialOpenForTesting: Bool

    init(containerFactory: (() throws -> AppContainer)? = nil) {
        self.containerFactory = containerFactory
        #if DEBUG
        if case nil = containerFactory {
            shouldFailInitialOpenForTesting = ProcessInfo.processInfo.arguments.contains(
                "-astra-test-store-open-failure-once"
            )
        } else {
            shouldFailInitialOpenForTesting = false
        }
        #else
        shouldFailInitialOpenForTesting = false
        #endif
    }

    func openIfNeeded() {
        guard !didAttemptOpen else { return }
        attemptOpen()
    }

    func retry() {
        guard case .failed = state else { return }
        attemptOpen()
    }

    private func attemptOpen() {
        didAttemptOpen = true
        state = .opening
        do {
            if shouldFailInitialOpenForTesting {
                shouldFailInitialOpenForTesting = false
                throw AstraError.server("Injected persistent-store startup failure for UI testing.")
            }
            let appContainer: AppContainer
            if let containerFactory {
                appContainer = try containerFactory()
            } else if AstraFeatureFlags.usesMockBackend {
                appContainer = AppContainer.preview()
            } else {
                appContainer = try AppContainer.live()
            }
            state = .ready(appContainer)
        } catch {
            // Keep the store and all its files in place. In particular, do
            // not substitute an in-memory ModelContainer: writes would look
            // successful and disappear at the next launch.
            state = .failed
        }
    }
}

private struct PersistentStoreRecoveryView: View {
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Saved data unavailable", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Astra Style couldn't open your saved data. Nothing was deleted. Check your device storage, then try again.")
        } actions: {
            Button(action: retry) {
                Text("Try again")
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, AstraSpacing.lg)
                    .padding(.vertical, AstraSpacing.sm)
            }
                .buttonStyle(.astraSecondary)
                .frame(maxWidth: 320)
                .accessibilityIdentifier("startup.store.retry")
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
    }
}
