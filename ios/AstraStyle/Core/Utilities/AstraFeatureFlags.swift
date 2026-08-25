//
//  AstraFeatureFlags.swift
//  AstraStyle
//
//  Small, explicit home for the handful of flags that change top-level app
//  behavior at launch rather than mid-session. Intentionally not a general
//  feature-flagging system (spec §28 keeps flag *management* server-side/
//  admin-only) — this is strictly a local dev/QA switch.
//

import Foundation

public enum AstraFeatureFlags {
    /// When `true`, `RootView` boots straight into `Features/Slice`'s
    /// `SliceRootView` instead of the normal `AppRouteState`-driven flow
    /// (see `Features/Slice/README.md` for what that module is and why it
    /// exists). Debug-only by construction — the `#if DEBUG` guard means
    /// this always evaluates to `false` in a Release build regardless of
    /// the environment, so the slice can never ship active.
    ///
    /// Enable by setting the `ASTRA_VERTICAL_SLICE` environment variable to
    /// `1` in the running scheme (Xcode: Product > Scheme > Edit Scheme >
    /// Run > Arguments > Environment Variables).
    public static var verticalSliceEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["ASTRA_VERTICAL_SLICE"] == "1"
        #else
        false
        #endif
    }

    /// When `true`, the app clears any persisted session and local data
    /// during launch, before routing.
    ///
    /// UI tests need a known starting state. Without this, the QA sweep
    /// inherited whatever session the last manual run left in the Keychain and
    /// opened on Home instead of Welcome — which made every assertion fail for
    /// a reason that had nothing to do with the screens under test.
    ///
    /// Set via a launch argument (`-astra-reset-state`), so it is reachable
    /// from XCUITest but not from a shipped build's normal startup path.
    public static var resetsStateOnLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("-astra-reset-state")
    }

    /// When `true`, authenticating routes
    /// straight to the five-tab shell instead of into §6.3–§6.10.
    ///
    /// Exists for tests whose subject is the shell rather than onboarding.
    /// `ScreenQAUITests` is about tab navigation and screen reachability; every
    /// step it walked to GET to a tab bar was a way for an onboarding change to
    /// break a test that has nothing to do with onboarding — which is exactly
    /// what happened when §6.3–§6.9 replaced the old single placeholder screen.
    /// The flow itself is covered end to end by `OnboardingFlowUITests`,
    /// including that finishing it lands in the shell, so nothing is lost by not
    /// walking it twice.
    ///
    /// Debug-only by construction, like `verticalSliceEnabled`: the `#if DEBUG`
    /// guard means a Release build ignores the argument entirely, so a bypass
    /// that exists only for tests cannot ship active even if someone finds a way
    /// to pass launch arguments to a distributed build. `-astra-reset-state`
    /// above is not gated that way; this one is, because skipping a required
    /// step (§6.5) is a bigger thing to get wrong than starting signed out.
    ///
    /// Usage: `-astra-skip-onboarding`.
    public static var skipsOnboarding: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-astra-skip-onboarding")
        #else
        false
        #endif
    }

    /// When `true`, the app runs against `AppContainer.preview()` — the
    /// in-memory mocks in `Core/Mocks` — and starts already signed in to a
    /// throwaway session, routed straight into §6.3.
    ///
    /// Exists for one thing the other flags cannot give a UI test: a run of
    /// §6.10 with a real Style DNA in it. Reaching that screen otherwise
    /// means a live `style-dna/generate` round trip, so without this the
    /// screen with the most content in the flow would be the one screen with
    /// no UI coverage of its layout — which is where Dynamic Type breaks
    /// first.
    ///
    /// Debug-only by construction, like `verticalSliceEnabled` and
    /// `skipsOnboarding`: a Release build ignores the argument entirely, so a
    /// switch that swaps the whole backend for mocks cannot ship reachable.
    ///
    /// Usage: `-astra-mock-backend`.
    public static var usesMockBackend: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-astra-mock-backend")
        #else
        false
        #endif
    }

    /// When `true`, first-run onboarding includes the deferred screens
    /// (goals, measurements, appearance, lifestyle, reference) so Debug
    /// UITests can still reach the §29 consent gate. Release ignores the
    /// argument. See ADR 0015.
    ///
    /// Usage: `-astra-full-onboarding`.
    public static var includesDeferredOnboardingSteps: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-astra-full-onboarding")
        #else
        false
        #endif
    }

    /// When `true`, Studio and Discover appear in the tab bar. Default is
    /// off: those tabs are specified but unfinished, and advertising
    /// "Not built yet" every session is the week-1 uninstall (ADR 0015).
    ///
    /// Usage: `-astra-show-unfinished-chrome`.
    public static var showsUnfinishedChrome: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-astra-show-unfinished-chrome")
        #else
        false
        #endif
    }

    /// Forces a theme at launch, overriding the stored preference.
    ///
    /// Needed because the app applies its OWN `.preferredColorScheme(...)`,
    /// which correctly wins over the simulator's `-UIUserInterfaceStyle`
    /// argument — so there was no way to exercise the light palette from a UI
    /// test. Spec §3 defines a full light palette and
    /// `docs/07-design-system.md` records a WCAG audit of it; without this the
    /// whole thing stays unverifiable, which is how a contrast bug survives.
    ///
    /// Usage: `-astra-theme light` (or `dark`, or `system`).
    public static var forcedTheme: ThemePreference? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-astra-theme"), i + 1 < args.count else {
            return nil
        }
        return ThemePreference(rawValue: args[i + 1])
    }

    /// Presents one real paywall context after the Debug tab shell appears.
    ///
    /// Screenshot QA needs to inspect every quota message without performing
    /// seven destructive/expensive setup sequences. Release ignores the
    /// argument entirely, so this cannot expose a paywall unexpectedly in a
    /// distributed build.
    ///
    /// Usage: `-astra-audit-paywall closetLimit`.
    public static var auditPaywallContext: PaywallContext? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-astra-audit-paywall"), i + 1 < args.count else {
            return nil
        }
        return PaywallContext(rawValue: args[i + 1])
        #else
        return nil
        #endif
    }
}
