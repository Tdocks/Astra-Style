//
//  ClosetViewMode.swift
//  AstraStyle
//
//  Spec §6.14 "Views: Editorial grid. Compact list. Color spectrum." —
//  which of the three layouts the closet is currently drawn in.
//
//  THIS TYPE IS THE SELECTION, NOT THE LAYOUT. Each case has a view that
//  takes the same four inputs in the same order — `ClosetItemGrid`,
//  `ClosetCompactList`, `ClosetColorSpectrum` — so the screen swaps one
//  for another and hands all three identical arguments. That symmetry is
//  deliberate and is the reason none of the three owns a fetch, a filter
//  or a sort of the caller's data: they are three renderings of one
//  array. `ClosetColorSpectrum` is the single exception and re-orders
//  what it is given, because ordering IS what that mode is.
//
//  WHY IT CARRIES RAW STRINGS AND IS `Codable`, RATHER THAN BEING A PLAIN
//  ENUM. The raw values are a persistence contract, not decoration. A
//  chosen view mode is a preference, and a preference that resets on
//  every launch is a control that keeps undoing itself — so this type is
//  written to survive `@AppStorage`/`UserDefaults`, which requires
//  exactly `RawRepresentable where RawValue == String`. Nothing here
//  stores anything: the screen that owns the selection owns the storage.
//  What this file owes it is raw values that do not move, and
//  `ClosetViewModeTests` pins them so that renaming a case cannot
//  silently drop every existing user back to the grid.
//
//  NONISOLATED AND `Sendable`. A value describing a choice, with no view
//  or view-model state in it, so it can be read wherever the choice
//  happens to be held. Only view models are `@MainActor` here.
//

import Foundation

/// Which of spec §6.14's three closet layouts is on screen.
///
/// Declaration order is the order the toggle offers them in, and it is
/// not alphabetical or arbitrary: the editorial grid is the default and
/// the richest, the compact list trades the photograph for density, and
/// the colour spectrum re-orders rather than re-draws. That is a
/// progression from "look at it" to "find something in it" to "see it as
/// a whole", which is the order a man reaches for them in.
public enum ClosetViewMode: String, CaseIterable, Identifiable, Codable, Sendable {

    /// The photograph-led grid of spec §6.14, and the default. Rendered by
    /// `ClosetItemGrid`, which predates this enum and is unchanged by it.
    case editorialGrid

    /// One garment per row, thumbnail-sized, for scanning a large closet.
    case compactList

    /// The closet regrouped and reordered by colour — see
    /// `ClosetColorSpectrumOrder` for what that ordering means.
    case colorSpectrum

    public var id: String { rawValue }

    /// The mode's name, as the toggle and VoiceOver say it.
    ///
    /// "Colour spectrum", not the spec's "Color spectrum": the spec is
    /// written in American English and this app's user-facing copy is
    /// British throughout ("Trousers", "Autumn", "Name, brand, or
    /// colour"). The identifier keeps the American spelling because every
    /// colour-related symbol in the codebase and every column in Postgres
    /// does — `primaryColor`, `AstraGarmentColor`, `primary_color`.
    public var displayName: String {
        switch self {
        case .editorialGrid:
            String(localized: "Editorial grid", comment: "Closet view mode: the photograph-led grid")
        case .compactList:
            String(localized: "Compact list", comment: "Closet view mode: one garment per row")
        case .colorSpectrum:
            String(localized: "Colour spectrum", comment: "Closet view mode: the closet grouped and ordered by colour")
        }
    }

    /// The SF Symbol standing for this mode.
    ///
    /// Never shown without its name somewhere the user can reach: the
    /// toggle draws this glyph on a control whose accessibility value is
    /// `displayName`, and the menu behind it lists all three in words.
    /// A grid and a list are legible as glyphs; a colour spectrum is not,
    /// and `ClosetViewModeToggle`'s header records what that costs and
    /// how the menu pays it.
    public var symbolName: String {
        switch self {
        case .editorialGrid: "square.grid.2x2"
        case .compactList: "list.bullet"
        case .colorSpectrum: "swatchpalette"
        }
    }
}
