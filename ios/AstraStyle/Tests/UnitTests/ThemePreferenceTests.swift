//
//  ThemePreferenceTests.swift
//  AstraStyleTests
//
//  Defect (visual QA sweep): `ios/project.yml`'s `UIUserInterfaceStyle:
//  Dark` Info.plist key hard-overrode SwiftUI's `.preferredColorScheme(...)`
//  at the UIKit level, so the app's own theme preference — and the entire
//  light palette spec §3 defines — was unreachable. The fix removes the
//  Info.plist override; these tests pin the two things that make that safe:
//  `ThemePreference.resolvedColorScheme` maps every case correctly, and
//  `AppSettings`'s default is still `.dark` (spec §3 "Dark mode — default"),
//  so a user who has never touched the theme setting sees no change.
//

import SwiftUI
import Testing
@testable import AstraStyle

@Suite("ThemePreference.resolvedColorScheme and AppSettings default")
struct ThemePreferenceTests {

    @Test("`.system` resolves to `nil` — SwiftUI follows the OS setting")
    func systemResolvesToNil() {
        #expect(ThemePreference.system.resolvedColorScheme == nil)
    }

    @Test("`.light` resolves to `.light`")
    func lightResolvesToLight() {
        #expect(ThemePreference.light.resolvedColorScheme == .light)
    }

    @Test("`.dark` resolves to `.dark`")
    func darkResolvesToDark() {
        #expect(ThemePreference.dark.resolvedColorScheme == .dark)
    }

    @MainActor
    @Test("AppSettings defaults to dark, per spec §3 \"Dark mode — default\"")
    func appSettingsDefaultsToDark() {
        let settings = AppSettings()
        #expect(settings.preferredColorScheme == .dark)
        #expect(settings.preferredColorScheme.resolvedColorScheme == .dark)
    }
}
