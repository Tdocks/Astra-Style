//
//  AstraTheme.swift
//  AstraStyle
//
//  Environment-injected facade over the design system tokens, plus a home for cross-cutting
//  theme state (currently: an optional in-app appearance override).
//

import SwiftUI

/// App-wide design system facade.
///
/// The individual token namespaces (`AstraColor`, `AstraTypography`, `AstraSpacing`,
/// `AstraMotion`) are plain static namespaces and already resolve correctly for the active
/// `ColorScheme` without any environment plumbing — most view code should just use them
/// directly (`AstraColor.textPrimary`, `.astraText(.body)`, etc).
///
/// `AstraTheme` exists for two things a static namespace can't do on its own:
/// 1. Give feature code a single `@Observable` object to inject/observe via the environment.
/// 2. Hold in-app appearance state, such as letting a user override the system color scheme
///    from Settings, independent of the device-wide setting.
@Observable
@MainActor
public final class AstraTheme {
    /// Optional in-app appearance override. `nil` means "follow system."
    public var colorSchemeOverride: ColorScheme?

    public init(colorSchemeOverride: ColorScheme? = nil) {
        self.colorSchemeOverride = colorSchemeOverride
    }
}

public extension EnvironmentValues {
    /// An app-owned appearance override, if one is injected. With no override,
    /// design tokens follow the system. Do not allocate an observable reference
    /// in the default getter: that changes its identity on every environment read.
    @Entry var astraTheme: AstraTheme? = nil
}

public extension View {
    /// Injects `theme` into the environment and applies its color scheme override (if any) to
    /// this view's subtree. Call once, near the root of the app:
    ///
    /// ```swift
    /// RootView()
    ///     .astraTheme(appContainer.theme)
    /// ```
    func astraTheme(_ theme: AstraTheme) -> some View {
        environment(\.astraTheme, theme)
            .preferredColorScheme(theme.colorSchemeOverride)
    }
}
