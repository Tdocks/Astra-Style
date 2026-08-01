//
//  ClosetColorSpectrumOrder.swift
//  AstraStyle
//
//  Spec §6.14's third view — "Color spectrum" — reduced to the only part
//  of it that can be measurably right or wrong: the ORDER.
//
//  WHY THIS IS A PURE FUNCTION AND NOT A COMPARATOR INSIDE A VIEW BODY.
//  The acceptance criterion for this half of the ticket reads, verbatim,
//  "Color spectrum view visually orders items by dominant color, verified
//  against a fixture set of items with known colors". That is a test
//  instruction, and a closure buried in a SwiftUI body cannot be handed a
//  fixture. So the ordering is a function of an array of garments and
//  nothing else, `ClosetColorSpectrum` renders what it returns, and the
//  criterion is met by `Tests/UnitTests/ClosetColorSpectrumOrderTests.swift`
//  rather than by looking at a screenshot. Same shape as `ClosetMetrics`,
//  and for the same reason.
//
//  1. WHAT "ORDERED BY DOMINANT COLOUR" MEANS HERE.
//  `ClosetItem.primaryColor` is free text, and `AstraGarmentColor` turns
//  the words this build knows into a packed `0xRRGGBB`. Sorting on that
//  integer is not a colour order — it is a sort by red channel, which
//  files burgundy (0x5E2233) next to green (0x3B5A40) and calls the
//  result a spectrum. Every swatch is therefore converted to HSL/HSV
//  here (there was no such helper anywhere in the codebase; `HSL` below
//  is it) and the order is built from hue and lightness, which is what
//  the eye is actually reading.
//
//  2. THE SPECTRUM IS TWO RAMPS, NOT ONE.
//  Hue is meaningless for black, charcoal, grey and bone. They sit at no
//  point on a colour wheel, and ordering them by whatever hue their hex
//  happens to compute to scatters them at random through the colours —
//  which reads as a broken sort, because it is one. Wardrobes organised
//  by colour in the real world never do this: the blacks, greys and
//  whites are their own run, ordered by DEPTH. So this produces a
//  chromatic block ordered round the wheel from red, and a neutral block
//  ordered dark to light. Inside every group, chromatic or neutral,
//  garments also run dark to light, so one sentence describes the whole
//  view: the groups go round the wheel, the garments go from deep to
//  pale.
//
//  3. THE COLOURS COME FIRST AND THE NEUTRALS SECOND.
//  A menswear closet is mostly neutral. Leading with the neutral ramp
//  would open this mode on a screenful of grey, which is the exact
//  opposite of what it is for — the whole claim of a colour-spectrum view
//  is that the closet reads as a colour story at a glance, and "at a
//  glance" means the first screenful. Neutrals are not hidden; they are
//  the last real group, with a header saying they are ordered by depth
//  rather than by hue so their absence from the wheel is stated rather
//  than left to look like a bug.
//

import Foundation

/// Orders a closet by colour, for spec §6.14's colour-spectrum view.
///
/// Nonisolated and `Sendable` by construction: every input is a value and
/// nothing here reads a view, a view model or a clock, so the ordering
/// can be computed on whichever actor is holding the array.
public enum ClosetColorSpectrumOrder {

    /// Above this much saturation *at a colour's own brightness*, a
    /// garment is treated as a colour and placed on the wheel; at or
    /// below it, as a neutral and placed on the depth ramp.
    ///
    /// WHY HSV SATURATION RATHER THAN THE TWO OBVIOUS ALTERNATIVES, both
    /// of which were tried against the real `AstraGarmentColor` table and
    /// both of which get a garment badly wrong:
    ///
    /// * HSL saturation blows up near white. "cream" scores 0.49 and
    ///   "sky blue" scores 0.46 — so an HSL-saturation test calls a
    ///   near-white beige more colourful than a blue shirt.
    /// * Absolute chroma (max channel minus min channel) collapses in the
    ///   dark. "forest green" scores 0.094 and "bone" scores 0.082 — so a
    ///   chroma test cannot tell a green from an off-white, because
    ///   forest green is dark rather than grey.
    ///
    /// HSV saturation — chroma divided by the colour's own brightness —
    /// separates all four correctly: cream 0.12, bone 0.09, sky blue
    /// 0.33, forest green 0.35.
    ///
    /// WHERE THE LINE SITS AND WHAT IT COSTS. 0.20 keeps the beige family
    /// menswear treats as neutral (bone, cream, ivory, ecru, oatmeal) on
    /// the depth ramp, and lets the tans (camel, tan, khaki) run as the
    /// warm colours they read as. The two nearest calls are "pale blue"
    /// at 0.181, which lands among the neutrals, and "sand" at 0.226,
    /// which joins the tans. Both are genuinely borderline; this is one
    /// constant to retune if a wardrobe proves either wrong, and the
    /// tests name the boundary explicitly so a change to it cannot be
    /// silent.
    public static let neutralSaturationCeiling: Double = 0.20

    /// At or below this lightness a swatch is a neutral whatever its
    /// saturation says.
    ///
    /// Only the dark end needs this. A near-white cannot have high HSV
    /// saturation — every channel is high, so the spread between them is
    /// small — but a near-black can: `0x0A0A14` is visibly black and
    /// scores 0.50, because half of very little is still half. Without
    /// this clause that garment would be filed as a blue.
    public static let nearBlackLightness: Double = 0.10

    /// The closet, ordered for the spectrum view. This is the function
    /// the acceptance criterion is written against.
    ///
    /// Total and deterministic: see `isOrderedBefore(_:_:)` for the full
    /// tiebreak chain and why it ends where it does.
    public static func ordered(_ items: [ClosetItem]) -> [ClosetItem] {
        entries(for: items).map(\.item)
    }

    /// The same order, cut into the groups the view draws headers for.
    ///
    /// `segments(for:).flatMap(\.items)` is `ordered(_:)` — asserted in
    /// the tests, because two orderings that can drift apart is exactly
    /// the bug this pairing would hide.
    public static func segments(for items: [ClosetItem]) -> [Segment] {
        let sorted = entries(for: items)
        return Band.allCases.compactMap { band in
            let inBand = sorted.filter { $0.band == band }
            guard !inBand.isEmpty else { return nil }
            return Segment(band: band, items: inBand.map(\.item), swatchHexes: distinctSwatchHexes(in: inBand))
        }
    }

    /// Where a colour word lands, or why it lands nowhere on the wheel.
    ///
    /// Public because it is the honest unit under test: the criterion is
    /// about known colour words producing known placements, and asserting
    /// that directly is stronger than inferring it from an array's order.
    public static func band(forColorNamed name: String?) -> Band {
        resolve(name).band
    }

    /// Where a resolved swatch lands. Separated from the name lookup so
    /// the band boundaries can be tested on hex values directly, without
    /// needing a colour word in `AstraGarmentColor` that happens to sit
    /// on each one.
    public static func band(for color: HSL) -> Band {
        color.isNeutral ? .neutral : Band.hueBand(containing: color.hue)
    }
}

// MARK: - Bands

extension ClosetColorSpectrumOrder {

    /// A group of the spectrum, in the order the view lays them out.
    ///
    /// Declaration order is layout order, and `rank` states it a second
    /// time as a number rather than leaving it as a consequence of how
    /// the cases happen to be written down. A test asserts the two agree,
    /// so reordering the declaration without meaning to cannot silently
    /// reorder the screen.
    ///
    /// SIX HUE BANDS, NOT TWELVE AND NOT SEVEN. The boundaries below are
    /// chosen so each band holds a family that reads as one thing, rather
    /// than sitting on an even 30° grid: an even grid splits "sky blue"
    /// (209°) away from "navy" (222°) and "indigo" (226°), which is a
    /// break no one looking at the screen could explain. There is
    /// deliberately no separate pink band — menswear pink arrives as a
    /// light red (rose, dusty pink, at 340–355°) and belongs with the
    /// reds; only true magenta sits between blue and red, and it is in
    /// the purple band where it belongs.
    public enum Band: String, CaseIterable, Identifiable, Sendable {

        /// 335°–15°. Reds, and the dark reds — burgundy, oxblood.
        case red
        /// 15°–45°. Rust and terracotta, and every brown and tan.
        case orange
        /// 45°–65°. Yellow, mustard, saffron, lemon.
        case yellow
        /// 65°–165°. Greens, and the olives at the yellow end of them.
        case green
        /// 165°–250°. Everything from sky blue through navy to indigo.
        case blue
        /// 250°–335°. Purples, plum, and magenta.
        case purple

        /// No usable hue: black, charcoal, grey, stone, bone, white, and
        /// the near-blacks. Ordered by depth rather than by the wheel.
        case neutral

        /// A colour word is on file and this build has no swatch for it.
        case unmappedColor

        /// No colour word on file at all.
        case noColorRecorded

        public var id: String { rawValue }

        /// Position in the layout. Stated rather than derived so that the
        /// order the screen reads in is a fact in one place.
        public var rank: Int {
            switch self {
            case .red: 0
            case .orange: 1
            case .yellow: 2
            case .green: 3
            case .blue: 4
            case .purple: 5
            case .neutral: 6
            case .unmappedColor: 7
            case .noColorRecorded: 8
            }
        }

        /// Whether garments in this band were placed by their colour.
        ///
        /// The two false cases are why this view needs headers at all: a
        /// silent tail of garments after the last colour reads as a
        /// sorting fault, so the view states what those groups are.
        public var isPlaced: Bool {
            switch self {
            case .red, .orange, .yellow, .green, .blue, .purple, .neutral: true
            case .unmappedColor, .noColorRecorded: false
            }
        }

        /// The group's name, as its header says it.
        ///
        /// "Oranges and browns" carries the second noun and "Greens" does
        /// not, because the asymmetry is real: olive genuinely is a green
        /// and nobody would look for it elsewhere, while nobody calls a
        /// brown jacket orange — brown is a dark orange to a colour wheel
        /// and to no one else.
        public var displayName: String {
            switch self {
            case .red:
                String(localized: "Reds", comment: "Closet colour spectrum group")
            case .orange:
                String(localized: "Oranges and browns", comment: "Closet colour spectrum group covering rust, terracotta, brown, camel and tan")
            case .yellow:
                String(localized: "Yellows", comment: "Closet colour spectrum group")
            case .green:
                String(localized: "Greens", comment: "Closet colour spectrum group, including the olives")
            case .blue:
                String(localized: "Blues", comment: "Closet colour spectrum group")
            case .purple:
                String(localized: "Purples", comment: "Closet colour spectrum group")
            case .neutral:
                String(localized: "Neutrals", comment: "Closet colour spectrum group: blacks, greys, bones and whites")
            case .unmappedColor:
                String(localized: "Not on the spectrum", comment: "Closet colour spectrum group for colour words this build has no swatch for")
            case .noColorRecorded:
                String(localized: "No colour on file", comment: "Closet colour spectrum group for garments with no colour recorded")
            }
        }

        /// One line under the header, where the group's position needs
        /// explaining. `nil` for the six hue bands, which explain
        /// themselves — a sentence under every group would be noise, and
        /// spec §6.14's boundaries are meant to be legible, not loud.
        public var explanation: String? {
            switch self {
            case .red, .orange, .yellow, .green, .blue, .purple:
                nil
            case .neutral:
                String(localized: "Ordered by depth rather than hue — black, grey, bone and white sit at no point on a colour wheel.", comment: "Why the neutral group is not part of the colour wheel")
            case .unmappedColor:
                String(localized: "Astra has no swatch for these colour words yet, so they are listed here rather than placed.", comment: "Why some garments cannot be positioned on the colour spectrum")
            case .noColorRecorded:
                String(localized: "Add a colour to a piece and it takes its place on the spectrum.", comment: "How to move a garment out of the no-colour group")
            }
        }

        /// The band a hue falls in. `hue` is expected in `0..<360`, which
        /// is what `HSL` always produces.
        static func hueBand(containing hue: Double) -> Band {
            switch hue {
            case ..<15: .red
            case ..<45: .orange
            case ..<65: .yellow
            case ..<165: .green
            case ..<250: .blue
            case ..<335: .purple
            // 335° and up wraps back onto red, which is where the dark
            // reds live: burgundy computes to 343° and oxblood to 350°.
            default: .red
            }
        }
    }
}

// MARK: - Segments

extension ClosetColorSpectrumOrder {

    /// One band's garments, already in order.
    ///
    /// Named `Segment` rather than the obvious `Group` or `Section`
    /// because both of those are SwiftUI types the rendering view uses in
    /// the same expression, and a shadowed `Group` is a compile error
    /// that reads like a typo.
    public struct Segment: Identifiable, Equatable, Sendable {

        /// Which part of the spectrum this is.
        public let band: Band

        /// The garments, in the order the view draws them.
        public let items: [ClosetItem]

        /// The distinct swatches actually present in this segment, in the
        /// same dark-to-light order the garments are in.
        ///
        /// Real resolved colours, never an invented "representative"
        /// colour for the band: `AstraGarmentColor`'s header is explicit
        /// that this app does not paint a rectangle it made up, and a
        /// single swatch standing for "Blues" would be exactly that.
        /// Empty for the two unplaced bands, which have no swatches by
        /// definition.
        public let swatchHexes: [UInt32]

        public var id: String { band.rawValue }

        fileprivate init(band: Band, items: [ClosetItem], swatchHexes: [UInt32]) {
            self.band = band
            self.items = items
            self.swatchHexes = swatchHexes
        }
    }
}

// MARK: - Colour geometry

extension ClosetColorSpectrumOrder {

    /// A packed `0xRRGGBB` swatch expressed the way the eye reads it.
    ///
    /// Carries HSV saturation alongside the HSL triple because the two
    /// saturations answer different questions and this file needs both:
    /// HSL's is the one that orders two garments of the same hue and
    /// lightness, HSV's is the one that decides whether a garment has a
    /// hue worth ordering by at all. See `neutralSaturationCeiling` for
    /// the worked cases where they disagree.
    ///
    /// A value type over a `UInt32`, with no `Color` and no UIKit in it,
    /// so the conversion is testable without a rendering context.
    public struct HSL: Equatable, Sendable {

        /// Degrees, `0..<360`, red at 0.
        ///
        /// `0` when the swatch has no hue at all (a pure grey). That is a
        /// convention, not a measurement — every such swatch is a neutral
        /// and is never ordered by hue.
        public let hue: Double

        /// HSL saturation, `0...1`.
        public let saturation: Double

        /// `0` is black, `1` is white.
        public let lightness: Double

        /// HSV saturation — chroma over the swatch's own brightness,
        /// `0...1`. This is the neutrality test.
        public let hsvSaturation: Double

        /// Whether this swatch belongs on the depth ramp rather than the
        /// colour wheel.
        public var isNeutral: Bool {
            hsvSaturation < ClosetColorSpectrumOrder.neutralSaturationCeiling
                || lightness <= ClosetColorSpectrumOrder.nearBlackLightness
        }

        /// Converts a packed `0xRRGGBB` sRGB value.
        ///
        /// Straight sRGB arithmetic, deliberately not a perceptual space.
        /// A CIELAB or OKLCH conversion would order hues slightly more
        /// evenly, and would put a colour-appearance model behind a
        /// wardrobe screen where the inputs are seventy hand-picked
        /// swatches — the precision would be spent on a table that was
        /// never that precise. Revisit if the palette ever comes from a
        /// vision model's measured pixels rather than from words.
        public init(hex: UInt32) {
            // Channel extraction mirrors `Color(hex:)` in AstraColor.swift
            // exactly, so a swatch is decomposed the same way whether it is
            // being drawn or being sorted.
            let red = Double((hex & 0xFF0000) >> 16) / 255
            let green = Double((hex & 0x00FF00) >> 8) / 255
            let blue = Double(hex & 0x0000FF) / 255

            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let delta = maximum - minimum
            let lightness = (maximum + minimum) / 2

            let rawHue: Double
            if delta == 0 {
                rawHue = 0
            } else if maximum == red {
                rawHue = 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if maximum == green {
                rawHue = 60 * ((blue - red) / delta + 2)
            } else {
                rawHue = 60 * ((red - green) / delta + 4)
            }

            self.hue = rawHue < 0 ? rawHue + 360 : rawHue
            self.lightness = lightness
            // `1 - abs(2L - 1)` is zero only at pure black and pure
            // white, and both of those have `delta == 0`, so the guard
            // above already covers the division.
            self.saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
            self.hsvSaturation = maximum == 0 ? 0 : delta / maximum
        }
    }
}

// MARK: - Resolution and sorting

extension ClosetColorSpectrumOrder {

    /// What one colour word resolved to: the band it lands in, and the
    /// swatch behind that decision where there was one.
    ///
    /// A named value rather than a tuple. The three members travel
    /// together everywhere and two of them are optionals of the same
    /// shape, which is exactly the pairing a positional tuple gets
    /// silently wrong at a call site.
    private struct Resolution {
        let band: Band
        let hex: UInt32?
        let color: HSL?
    }

    /// One garment with its colour already resolved.
    ///
    /// The resolution happens once per garment rather than inside the
    /// comparator, which would repeat a string trim, a dictionary lookup
    /// and a colour conversion on the order of `n log n` times. For a
    /// closet of 500 that is the difference between one pass and about
    /// nine thousand.
    private struct Entry {
        let item: ClosetItem
        let band: Band
        /// `nil` for the two unplaced bands, which have no swatch.
        let hex: UInt32?
        /// `nil` for the two unplaced bands, which have no geometry.
        let color: HSL?

        init(item: ClosetItem) {
            let resolved = ClosetColorSpectrumOrder.resolve(item.primaryColor)
            self.item = item
            self.band = resolved.band
            self.hex = resolved.hex
            self.color = resolved.color
        }
    }

    /// Where one colour word lands, and everything needed to order it.
    ///
    /// THE TWO UNPLACED CASES ARE KEPT APART, NOT MERGED. A garment with
    /// no colour on file and a garment whose colour word this build has
    /// never heard of are both off the wheel, but they are not the same
    /// thing to the man reading the screen: the first is a field he can
    /// fill in, the second is a word Astra does not know and there is
    /// nothing for him to do about it. Collapsing them into one "other"
    /// group would force a single sentence to cover both, and it would be
    /// wrong for one of them — the same reasoning `ClosetMetrics` records
    /// under "unknown is a case, not a zero".
    private static func resolve(_ name: String?) -> Resolution {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Resolution(band: .noColorRecorded, hex: nil, color: nil)
        }
        // `AstraGarmentColor` does its own trimming, lowercasing and
        // last-word fallback, so "Tobacco Brown" resolves through the same
        // path the swatch beside the word does. A `nil` hex is that file's
        // deliberate answer for a word this build has no swatch for, and
        // is honoured here rather than second-guessed with a default.
        guard let hex = AstraGarmentColor.swatch(for: name).hex else {
            return Resolution(band: .unmappedColor, hex: nil, color: nil)
        }
        let color = HSL(hex: hex)
        return Resolution(band: band(for: color), hex: hex, color: color)
    }

    private static func entries(for items: [ClosetItem]) -> [Entry] {
        items.map(Entry.init(item:)).sorted(by: isOrderedBefore)
    }

    /// The total order.
    ///
    /// WHY IT HAS TO BE TOTAL. `Array.sorted(by:)` is not documented as
    /// stable, so any pair the comparator calls equal may come back in
    /// either order, and may come back in a different order next time the
    /// closet is fetched. Two navy jumpers swapping places between
    /// renders is not a cosmetic wobble on this screen — it is the one
    /// thing a view whose entire claim is "these are in order" cannot do.
    /// So the chain below never runs out of keys.
    ///
    /// The keys, in order, and what each is for:
    ///
    /// 1. `band` — which group, per `Band.rank`.
    /// 2. `lightness` — dark to light, the ramp inside every group.
    /// 3. `hue` — separates two garments of the same depth within a band.
    /// 4. `saturation` — separates a muted and a vivid shade of one hue at
    ///    one depth; with 1-4 the SWATCH is fully ordered, since hue,
    ///    saturation and lightness reconstruct the hex exactly.
    /// 5. `name` — from here on the two garments are the same colour, so
    ///    the tiebreak stops being about colour and starts being about
    ///    reading order. Compared with `<` rather than a localised
    ///    comparison on purpose: this must produce the same answer on
    ///    every device and in every locale, and a locale-sensitive
    ///    ordering would make the same closet order differently abroad.
    /// 6. `id` — the guarantee. Unique by construction and immutable, so
    ///    the comparator cannot return equal for two distinct garments,
    ///    and the order does not depend on how the array arrived.
    private static func isOrderedBefore(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.band != rhs.band {
            return lhs.band.rank < rhs.band.rank
        }
        if let left = lhs.color, let right = rhs.color, left != right {
            if left.lightness != right.lightness {
                return left.lightness < right.lightness
            }
            if left.hue != right.hue {
                return left.hue < right.hue
            }
            if left.saturation != right.saturation {
                return left.saturation < right.saturation
            }
        }
        if lhs.item.name != rhs.item.name {
            return lhs.item.name < rhs.item.name
        }
        return lhs.item.id.uuidString < rhs.item.id.uuidString
    }

    /// The swatches present in a run of garments, deduplicated, first
    /// appearance winning so the run stays in the garments' own order.
    private static func distinctSwatchHexes(in entries: [Entry]) -> [UInt32] {
        var seen: Set<UInt32> = []
        var hexes: [UInt32] = []
        for hex in entries.compactMap(\.hex) where seen.insert(hex).inserted {
            hexes.append(hex)
        }
        return hexes
    }
}
