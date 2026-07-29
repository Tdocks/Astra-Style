//
//  AstraStyleApp.swift
//  AstraStyle
//
//  App entry point. Matches spec §27 "Sample Root App Structure" exactly:
//  a single `AppContainer` is created once, injected into the environment,
//  and `RootView` switches on `AppRouter.routeState`.
//

import SwiftUI

@main
struct AstraStyleApp: App {
    @State private var appContainer = AppContainer.live()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appContainer)
                .environment(router)
                .environment(appContainer.sessionStore)
                .preferredColorScheme(appContainer.settings.preferredColorScheme.resolvedColorScheme)
                .task {
                    await bootstrap()
                }
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
    private func bootstrap() async {
        let route = await withMinimumDuration(Self.splashMinimumDwell) {
            await self.resolveLaunchRoute()
        }
        router.routeState = route
    }

    private func resolveLaunchRoute() async -> AppRouteState {
        if AstraFeatureFlags.resetsStateOnLaunch {
            // UI-test entry point only (see AstraFeatureFlags). Clears the
            // Keychain session so the sweep starts from Welcome regardless of
            // what a previous run left behind.
            try? await appContainer.sessionStore.signOut()
            return .signedOut
        }

        // Reading the Keychain is instant; `restoreSession()` only touches the
        // network when the stored token has actually expired. Bounded anyway,
        // because "only sometimes hangs" is still hangs.
        let restored = await withDeadline(Self.splashDeadline) {
            try await appContainer.sessionStore.restoreSession()
        }

        let session: AuthSession?
        switch restored {
        case .success(let value):
            session = value
        case .timedOut, .failed:
            session = nil
        }

        guard let session else {
            // No stored session, or restoring it failed or timed out. All
            // resolve to Welcome: without credentials there is nothing else to
            // show.
            return .signedOut
        }

        if session.isGuest {
            // Guest sessions have no server-side profile row (ADR 0011: "no
            // server-side identity at all"), so there is nothing to fetch —
            // doing so anyway would be a real network call for a session that
            // must never touch Supabase, and would fail besides, since a
            // guest's access token is empty.
            //
            // This scaffold does not yet persist a local "guest completed
            // onboarding" flag, so a restored guest always lands on `.main`
            // rather than resuming a specific onboarding step. ADR 0011 names
            // this gap explicitly under its negative consequences.
            return .main
        }

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
