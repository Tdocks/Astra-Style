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
}
