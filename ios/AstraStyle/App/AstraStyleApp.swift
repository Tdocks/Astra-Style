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
    private func bootstrap() async {
        do {
            let session = try await appContainer.sessionStore.restoreSession()
            if session == nil {
                router.routeState = .signedOut
                return
            }
            let profile = try await appContainer.profileRepository.fetchCurrentProfile()
            router.routeState = (profile.onboardingCompletedAt != nil) ? .main : .onboarding
        } catch {
            // Session restoration failure is treated as signed-out rather
            // than surfacing an error screen at launch; the user can retry
            // sign-in from Welcome.
            router.routeState = .signedOut
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
