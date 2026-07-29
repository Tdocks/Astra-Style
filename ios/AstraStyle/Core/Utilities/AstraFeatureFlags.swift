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

    /// When `true`, the app clears any persisted session and local guest data
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
}
