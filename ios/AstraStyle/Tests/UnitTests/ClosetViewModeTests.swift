//
//  ClosetViewModeTests.swift
//  AstraStyleTests
//
//  Spec §6.14 "Views: Editorial grid. Compact list. Color spectrum."
//
//  A three-case enum does not normally earn a test file. This one does,
//  for one reason: its raw values are a persistence contract. The chosen
//  view mode is a preference and is meant to survive a launch, which puts
//  the raw strings into `UserDefaults` — and a raw string in
//  `UserDefaults` is the only kind of rename that compiles cleanly, ships
//  cleanly, and silently drops every existing user back to the default
//  the first time they open the tab. The round-trip tests below are what
//  turns that rename into a failing build.
//
//  The second reason is smaller and still real: `allCases` order is the
//  order the toggle offers the modes in, and it is stated as an argument
//  in `ClosetViewMode`'s own doc comment rather than left to chance.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("ClosetViewMode — spec §6.14 closet view modes")
struct ClosetViewModeTests {

    @Test("The raw values are exactly what a stored preference will hold, so renaming a case is a failing test rather than a silent reset for everyone who had chosen a mode")
    func rawValuesArePinned() {
        #expect(ClosetViewMode.editorialGrid.rawValue == "editorialGrid")
        #expect(ClosetViewMode.compactList.rawValue == "compactList")
        #expect(ClosetViewMode.colorSpectrum.rawValue == "colorSpectrum")
    }

    @Test("Every mode survives a round trip through its raw value, which is the whole of what UserDefaults-backed storage does with it")
    func rawValueRoundTrip() {
        for mode in ClosetViewMode.allCases {
            #expect(ClosetViewMode(rawValue: mode.rawValue) == mode)
        }
    }

    @Test("A stored value this build does not recognise decodes to nothing rather than to the first case, so a preference written by a later build falls back visibly")
    func unknownRawValuesDoNotResolve() {
        #expect(ClosetViewMode(rawValue: "colourSpectrum") == nil)
        #expect(ClosetViewMode(rawValue: "") == nil)
        #expect(ClosetViewMode(rawValue: "gallery") == nil)
    }

    @Test("Every mode survives a JSON round trip, so the same value can be carried in a draft or a settings payload as well as in UserDefaults")
    func codableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(ClosetViewMode.allCases)
        let decoded = try JSONDecoder().decode([ClosetViewMode].self, from: encoded)

        #expect(decoded == ClosetViewMode.allCases)
    }

    @Test("The identifier is the raw value, so a mode used as a ForEach identity and a mode written to storage cannot drift into two different strings")
    func identifierIsTheRawValue() {
        for mode in ClosetViewMode.allCases {
            #expect(mode.id == mode.rawValue)
        }
    }

    @Test("The modes are offered grid first, then list, then spectrum — the progression the enum's own doc comment argues for, not alphabetical order")
    func allCasesIsInOfferingOrder() {
        #expect(ClosetViewMode.allCases == [.editorialGrid, .compactList, .colorSpectrum])
    }

    @Test("Each mode has a name and a glyph of its own, because a menu row where two modes read alike would be a control the user cannot aim")
    func namesAndGlyphsAreDistinct() {
        let names = ClosetViewMode.allCases.map(\.displayName)
        let symbols = ClosetViewMode.allCases.map(\.symbolName)

        #expect(Set(names).count == ClosetViewMode.allCases.count)
        #expect(Set(symbols).count == ClosetViewMode.allCases.count)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(symbols.allSatisfy { !$0.isEmpty })
    }
}
