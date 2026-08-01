//
//  ClosetColorSpectrumOrderTests.swift
//  AstraStyleTests
//
//  Spec §6.14 "Closet overview" — the third view, "Color spectrum" — and
//  P3-CLOSET-04's second acceptance criterion, verbatim: "Color spectrum
//  view visually orders items by dominant color, verified against a
//  fixture set of items with known colors."
//
//  That criterion is a test instruction, and this file is the test. The
//  fixtures below are garments whose colour words `AstraGarmentColor`
//  resolves to known swatches, so "verified against a fixture set of
//  items with known colors" is met literally: every expected order in
//  this file is derived from the hue and lightness those swatches
//  actually compute to, not from the order the fixtures were written in.
//
//  Three suites, in the order the argument runs:
//
//  1. The colour conversion on its own, on values whose HSL is textbook
//     (pure red, pure cyan, mid grey), so a wrong ordering can be traced
//     to the arithmetic or ruled out of it in one step.
//  2. Where a colour word lands, asserted directly rather than inferred
//     from an array's order.
//  3. The order itself, including the three cases a spectrum view gets
//     wrong: neutrals scattered through the hues, unplaceable colours
//     left as a silent tail, and two garments of one colour swapping
//     places between renders.
//

import Foundation
import Testing
@testable import AstraStyle

/// Double comparison with a tolerance, since every value here is the
/// result of a division. Tight enough that a wrong formula fails and a
/// rounding difference does not.
private func isClose(_ value: Double, _ expected: Double, tolerance: Double = 0.0005) -> Bool {
    abs(value - expected) < tolerance
}

@Suite("ClosetColorSpectrumOrder.HSL — hex to colour geometry (spec §6.14)")
struct ClosetColorSpectrumHSLTests {

    @Test("The six primaries and secondaries land on the textbook hues, which is what makes the wheel order in the view a spectrum rather than an arbitrary rotation")
    func primaryAndSecondaryHues() {
        #expect(isClose(ClosetColorSpectrumOrder.HSL(hex: 0xFF0000).hue, 0))
        #expect(isClose(ClosetColorSpectrumOrder.HSL(hex: 0xFFFF00).hue, 60))
        #expect(isClose(ClosetColorSpectrumOrder.HSL(hex: 0x00FF00).hue, 120))
        #expect(isClose(ClosetColorSpectrumOrder.HSL(hex: 0x00FFFF).hue, 180))
        #expect(isClose(ClosetColorSpectrumOrder.HSL(hex: 0x0000FF).hue, 240))
        #expect(isClose(ClosetColorSpectrumOrder.HSL(hex: 0xFF00FF).hue, 300))
    }

    @Test("A hue that computes negative is wrapped into 0..<360 rather than left negative, because a negative hue would sort before red and break the wheel")
    func negativeHuesAreWrapped() {
        // Magenta is the case that computes to -60 before wrapping: red is
        // the maximum channel and blue is above green.
        let magenta = ClosetColorSpectrumOrder.HSL(hex: 0xFF00FF)
        #expect(magenta.hue >= 0)
        #expect(magenta.hue < 360)
        #expect(isClose(magenta.hue, 300))
    }

    @Test("A fully saturated primary reports saturation 1 and lightness 0.5, and a half-value primary reports the same saturation at half the lightness")
    func saturationAndLightnessOfPrimaries() {
        let red = ClosetColorSpectrumOrder.HSL(hex: 0xFF0000)
        #expect(isClose(red.saturation, 1))
        #expect(isClose(red.lightness, 0.5))
        #expect(isClose(red.hsvSaturation, 1))

        // 0x808000 is the classic olive: the same hue as yellow, fully
        // saturated, at half the lightness.
        let olive = ClosetColorSpectrumOrder.HSL(hex: 0x808000)
        #expect(isClose(olive.hue, 60))
        #expect(isClose(olive.saturation, 1))
        #expect(isClose(olive.lightness, 0.25098))
    }

    @Test("Black, white and mid grey report no saturation and no hue, so nothing in the greyscale can be ordered by a hue it does not have")
    func greyscaleHasNoHue() {
        let black = ClosetColorSpectrumOrder.HSL(hex: 0x000000)
        #expect(isClose(black.lightness, 0))
        #expect(isClose(black.saturation, 0))
        #expect(isClose(black.hsvSaturation, 0))
        #expect(isClose(black.hue, 0))

        let white = ClosetColorSpectrumOrder.HSL(hex: 0xFFFFFF)
        #expect(isClose(white.lightness, 1))
        #expect(isClose(white.saturation, 0))

        let grey = ClosetColorSpectrumOrder.HSL(hex: 0x808080)
        #expect(isClose(grey.lightness, 0.50196))
        #expect(isClose(grey.saturation, 0))
        #expect(isClose(grey.hsvSaturation, 0))
    }
}

@Suite("ClosetColorSpectrumOrder — what counts as a neutral (spec §6.14)")
struct ClosetColorSpectrumNeutralTests {

    /// The counterexample HSL saturation gets wrong. `cream` scores 0.49
    /// on HSL saturation and `sky blue` scores 0.46, so an HSL-saturation
    /// test would call a near-white beige the more colourful of the two.
    @Test("Cream is read as a neutral and sky blue as a colour, even though HSL saturation rates cream the more saturated of the two")
    func hslSaturationWouldGetTheBeigesWrong() {
        let cream = ClosetColorSpectrumOrder.HSL(hex: 0xF0E7D3)
        let skyBlue = ClosetColorSpectrumOrder.HSL(hex: 0x8FB4D6)

        #expect(cream.saturation > skyBlue.saturation)
        #expect(cream.isNeutral)
        #expect(skyBlue.isNeutral == false)
    }

    /// The counterexample absolute chroma gets wrong. `forest green`
    /// spans 0.094 between its highest and lowest channel and `bone`
    /// spans 0.082 — nearly the same — because forest green is dark, not
    /// because it is grey.
    @Test("Forest green is read as a colour and bone as a neutral, even though the two span almost the same absolute chroma")
    func absoluteChromaWouldGetTheDarkColoursWrong() {
        let forestGreen = ClosetColorSpectrumOrder.HSL(hex: 0x2C4433)
        let bone = ClosetColorSpectrumOrder.HSL(hex: 0xEDE6D8)

        #expect(forestGreen.isNeutral == false)
        #expect(bone.isNeutral)
        // The measure that separates them: chroma over the colour's own
        // brightness, rather than chroma on its own.
        #expect(forestGreen.hsvSaturation > bone.hsvSaturation)
    }

    @Test("A near-black with a strong colour cast is still a neutral, because half of a very small brightness is a colour nobody can see")
    func nearBlackIsNeutralWhateverItsSaturationSays() {
        let nearBlack = ClosetColorSpectrumOrder.HSL(hex: 0x0A0A14)

        #expect(nearBlack.hsvSaturation > ClosetColorSpectrumOrder.neutralSaturationCeiling)
        #expect(nearBlack.lightness <= ClosetColorSpectrumOrder.nearBlackLightness)
        #expect(nearBlack.isNeutral)
    }

    @Test("The neutral boundary sits where the file says it sits, so moving the constant is a deliberate change rather than a quiet one")
    func theNeutralBoundaryIsWhereItIsDocumented() {
        #expect(ClosetColorSpectrumOrder.neutralSaturationCeiling == 0.20)
        #expect(ClosetColorSpectrumOrder.nearBlackLightness == 0.10)
    }
}

@Suite("ClosetColorSpectrumOrder — where a colour word lands (spec §6.14)")
struct ClosetColorSpectrumBandTests {

    private typealias Band = ClosetColorSpectrumOrder.Band

    @Test("Every hue band boundary falls where the file documents it, so a band that quietly widens is a failing test rather than a garment in the wrong group")
    func hueBandBoundaries() {
        #expect(Band.hueBand(containing: 0) == .red)
        #expect(Band.hueBand(containing: 14.9) == .red)
        #expect(Band.hueBand(containing: 15) == .orange)
        #expect(Band.hueBand(containing: 44.9) == .orange)
        #expect(Band.hueBand(containing: 45) == .yellow)
        #expect(Band.hueBand(containing: 64.9) == .yellow)
        #expect(Band.hueBand(containing: 65) == .green)
        #expect(Band.hueBand(containing: 164.9) == .green)
        #expect(Band.hueBand(containing: 165) == .blue)
        #expect(Band.hueBand(containing: 249.9) == .blue)
        #expect(Band.hueBand(containing: 250) == .purple)
        #expect(Band.hueBand(containing: 334.9) == .purple)
    }

    @Test("Hues past 335 degrees wrap back onto the reds, which is where the dark reds compute to — burgundy at 343 and oxblood at 350")
    func theWheelWrapsOntoRed() {
        #expect(Band.hueBand(containing: 335) == .red)
        #expect(Band.hueBand(containing: 359.9) == .red)
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "burgundy") == .red)
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "oxblood") == .red)
    }

    @Test("Known colour words land in the band a reader would put them in, which is the claim the whole view rests on")
    func knownWordsLandWhereTheyBelong() {
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "barn red") == .red)
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "rust") == .orange)
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "camel") == .orange)
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "mustard") == .yellow)
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "olive") == .green)
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "forest green") == .green)
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "navy") == .blue)
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "sky blue") == .blue)
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "plum") == .purple)
    }

    @Test("Brown and camel are colours on the wheel rather than neutrals, which is why the group that holds them is named for browns as well as oranges")
    func brownsAreColoursNotNeutrals() {
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "brown") == .orange)
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "tobacco brown") == .orange)
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "khaki") == .orange)
    }

    @Test("The greys, blacks, whites and beiges all land in one neutral group rather than scattering through the hues their hex happens to compute to")
    func neutralsAreOneGroup() {
        for word in ["black", "charcoal", "grey", "stone", "washed grey", "bone", "cream", "ivory", "oatmeal", "white", "bright white"] {
            #expect(ClosetColorSpectrumOrder.band(forColorNamed: word) == .neutral, "\(word) should be a neutral")
        }
    }

    @Test("A modifier in front of a known colour resolves through the same last-word rule the swatch beside the word uses, rather than falling off the spectrum")
    func modifiedWordsResolveThroughTheSwatchTable() {
        // "light blue" is not in the table; its last word is.
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "light blue") == .blue)
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "faded indigo") == .blue)
    }

    @Test("A colour word this build has no swatch for is placed nowhere on the wheel rather than guessed at, and is kept apart from a garment with no colour at all")
    func unplaceableWordsAreTwoDistinctCases() {
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "burnt sienna") == .unmappedColor)
        // The server's category words are not colours, and this is how
        // they should render — see `AstraGarmentColor`'s own header.
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "neon brights") == .unmappedColor)
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: nil) == .noColorRecorded)
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "") == .noColorRecorded)
        #expect(ClosetColorSpectrumOrder.band(forColorNamed: "   ") == .noColorRecorded)
    }

    @Test("The declared order of the bands is the order they are laid out in, so reordering the cases without meaning to cannot reorder the screen")
    func declarationOrderMatchesLayoutOrder() {
        #expect(Band.allCases.map(\.rank) == Array(0..<Band.allCases.count))
        #expect(Band.allCases.first == .red)
        #expect(Band.allCases.last == .noColorRecorded)
    }

    @Test("Every group that is not part of the wheel carries a line saying why, so a run of garments past the last colour is never left unexplained")
    func offWheelGroupsAlwaysExplainThemselves() {
        #expect(Band.neutral.explanation != nil)
        #expect(Band.unmappedColor.explanation != nil)
        #expect(Band.noColorRecorded.explanation != nil)
        #expect(Band.unmappedColor.isPlaced == false)
        #expect(Band.noColorRecorded.isPlaced == false)

        // The six hue bands are silent on purpose: a sentence under a
        // header reading "Blues" over a screenful of blue is noise.
        for band in [Band.red, .orange, .yellow, .green, .blue, .purple] {
            #expect(band.explanation == nil)
            #expect(band.isPlaced)
        }
    }
}

/// P3-CLOSET-04 acceptance criterion 2, verbatim: "Color spectrum view
/// visually orders items by dominant color, verified against a fixture
/// set of items with known colors."
///
/// Every fixture below carries a colour word `AstraGarmentColor` resolves
/// to a swatch this build ships, and every expected order is the one
/// those swatches' hues and lightnesses produce — so a failure here is a
/// real disagreement about colour, not a disagreement about fixtures.
@Suite("ClosetColorSpectrumOrder.ordered — P3-CLOSET-04 acceptance criterion 2")
struct ClosetColorSpectrumOrderingTests {

    private static let userID = UUID()

    private func makeItem(name: String, color: String? = nil, id: UUID = UUID()) -> ClosetItem {
        ClosetItem(
            id: id,
            userID: Self.userID,
            name: name,
            category: .top,
            primaryColor: color
        )
    }

    // MARK: - The wheel

    @Test("A rainbow of known colour words comes back in wheel order, red through purple, rather than in the order it was handed over")
    func chromaticsComeBackInWheelOrder() {
        let items = [
            makeItem(name: "Plum knit", color: "plum"),
            makeItem(name: "Navy crewneck", color: "navy"),
            makeItem(name: "Forest fleece", color: "forest green"),
            makeItem(name: "Mustard cardigan", color: "mustard"),
            makeItem(name: "Rust corduroy", color: "rust"),
            makeItem(name: "Barn red overshirt", color: "barn red")
        ]

        #expect(ClosetColorSpectrumOrder.ordered(items).map(\.name) == [
            "Barn red overshirt",
            "Rust corduroy",
            "Mustard cardigan",
            "Forest fleece",
            "Navy crewneck",
            "Plum knit"
        ])
    }

    @Test("Inside one band the garments run dark to light, so navy and sky blue sit at opposite ends of the blues instead of interleaving on hue noise")
    func withinABandTheOrderIsDarkToLight() {
        let items = [
            makeItem(name: "Sky oxford", color: "sky blue"),
            makeItem(name: "Blue chambray", color: "blue"),
            makeItem(name: "Navy crewneck", color: "navy"),
            makeItem(name: "Ink blazer", color: "ink blue")
        ]

        #expect(ClosetColorSpectrumOrder.ordered(items).map(\.name) == [
            "Navy crewneck",
            "Ink blazer",
            "Blue chambray",
            "Sky oxford"
        ])
    }

    // MARK: - Neutrals

    @Test("The neutrals are one block after every colour, ordered black to white, rather than scattered through the hues their hex computes to")
    func neutralsAreOneBlockAfterTheColours() {
        let items = [
            makeItem(name: "White tee", color: "white"),
            makeItem(name: "Grey sweat", color: "grey"),
            makeItem(name: "Navy crewneck", color: "navy"),
            makeItem(name: "Black tie shirt", color: "black"),
            makeItem(name: "Charcoal flannel", color: "charcoal"),
            makeItem(name: "Barn red overshirt", color: "barn red")
        ]

        #expect(ClosetColorSpectrumOrder.ordered(items).map(\.name) == [
            "Barn red overshirt",
            "Navy crewneck",
            "Black tie shirt",
            "Charcoal flannel",
            "Grey sweat",
            "White tee"
        ])
    }

    // MARK: - Everything that cannot be placed

    @Test("A colour word with no swatch and a garment with no colour at all form two named groups at the end, in that order, rather than one silent tail")
    func unplaceableGarmentsFormTwoGroupsAtTheEnd() {
        let items = [
            makeItem(name: "Anonymous tee"),
            makeItem(name: "Sienna camp shirt", color: "burnt sienna"),
            makeItem(name: "Grey sweat", color: "grey"),
            makeItem(name: "Blank colour tee", color: "   "),
            makeItem(name: "Navy crewneck", color: "navy")
        ]

        #expect(ClosetColorSpectrumOrder.ordered(items).map(\.name) == [
            "Navy crewneck",
            "Grey sweat",
            "Sienna camp shirt",
            "Anonymous tee",
            "Blank colour tee"
        ])
    }

    @Test("A closet where nothing resolves still comes back in a defined order, alphabetically, rather than in whatever order the fetch happened to return")
    func aClosetWithNoResolvableColoursIsStillOrdered() {
        let items = [
            makeItem(name: "Zephyr shell", color: "burnt sienna"),
            makeItem(name: "Alpine smock", color: "gunmetal"),
            makeItem(name: "Meridian shirt", color: "seafoam")
        ]

        let ordered = ClosetColorSpectrumOrder.ordered(items)

        #expect(ordered.map(\.name) == ["Alpine smock", "Meridian shirt", "Zephyr shell"])
        #expect(ClosetColorSpectrumOrder.segments(for: items).map(\.band) == [.unmappedColor])
    }

    // MARK: - Degenerate closets

    @Test("An empty closet produces an empty order and no groups, rather than a group with nothing in it")
    func emptyCloset() {
        #expect(ClosetColorSpectrumOrder.ordered([]).isEmpty)
        #expect(ClosetColorSpectrumOrder.segments(for: []).isEmpty)
    }

    @Test("A closet of one garment produces one group holding it, which is correct rather than a degenerate case to suppress")
    func singleGarment() throws {
        let only = makeItem(name: "Navy crewneck", color: "navy")
        let segments = ClosetColorSpectrumOrder.segments(for: [only])
        let segment = try #require(segments.first)

        #expect(segments.count == 1)
        #expect(segment.band == .blue)
        #expect(segment.items.map(\.id) == [only.id])
    }
}

/// The half of the criterion that a single expected array cannot show:
/// that the order is the same one every time, whoever hands the closet
/// over and in whatever order. `Array.sorted(by:)` is not documented as
/// stable, so any pair the comparator calls equal is free to come back
/// either way round — which on this screen would mean two navy jumpers
/// swapping places between renders.
@Suite("ClosetColorSpectrumOrder — stability and grouping (spec §6.14)")
struct ClosetColorSpectrumStabilityTests {

    private static let userID = UUID()

    private func makeItem(name: String, color: String? = nil, id: UUID = UUID()) -> ClosetItem {
        ClosetItem(id: id, userID: Self.userID, name: name, category: .top, primaryColor: color)
    }

    /// Deliberately full of ties: four navies, two greys, and two
    /// garments with no colour at all.
    private var tiedCloset: [ClosetItem] {
        [
            makeItem(name: "Zephyr crewneck", color: "navy"),
            makeItem(name: "Alpine crewneck", color: "navy"),
            makeItem(name: "Meridian crewneck", color: "navy"),
            makeItem(name: "Harbour crewneck", color: "navy"),
            makeItem(name: "Grey sweat", color: "grey"),
            makeItem(name: "Grey hoodie", color: "grey"),
            makeItem(name: "Anonymous tee"),
            makeItem(name: "Field jacket"),
            makeItem(name: "Rust corduroy", color: "rust")
        ]
    }

    @Test("The same closet ordered twice gives the same answer, so nothing on this screen moves between two renders of one array")
    func repeatedCallsAgree() {
        let items = tiedCloset
        let first = ClosetColorSpectrumOrder.ordered(items).map(\.id)
        let second = ClosetColorSpectrumOrder.ordered(items).map(\.id)

        #expect(first == second)
    }

    @Test("Every rotation and the reversal of one closet order identically, so a garment added at the front cannot reshuffle the pieces around it")
    func orderIsIndependentOfInputOrder() {
        let items = tiedCloset
        let baseline = ClosetColorSpectrumOrder.ordered(items).map(\.id)

        #expect(ClosetColorSpectrumOrder.ordered(items.reversed()).map(\.id) == baseline)

        for offset in 1..<items.count {
            let rotated = Array(items[offset...] + items[..<offset])
            #expect(ClosetColorSpectrumOrder.ordered(rotated).map(\.id) == baseline)
        }
    }

    @Test("Two garments of exactly one colour are separated by name, so a block of navy reads alphabetically rather than arbitrarily")
    func garmentsOfOneColourAreOrderedByName() {
        let ordered = ClosetColorSpectrumOrder.ordered(tiedCloset).map(\.name)
        let navies = ordered.filter { $0.hasSuffix("crewneck") }

        #expect(navies == ["Alpine crewneck", "Harbour crewneck", "Meridian crewneck", "Zephyr crewneck"])
    }

    @Test("Two garments with the same colour and the same name fall through to their identifier, which is unique by construction, so the comparator never runs out of keys")
    func identicalGarmentsAreSeparatedByIdentifier() throws {
        let first = try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000AA"))
        let second = try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000BB"))

        let items = [
            makeItem(name: "Navy jumper", color: "navy", id: second),
            makeItem(name: "Navy jumper", color: "navy", id: first)
        ]

        #expect(ClosetColorSpectrumOrder.ordered(items).map(\.id) == [first, second])
        #expect(ClosetColorSpectrumOrder.ordered(items.reversed()).map(\.id) == [first, second])
    }

    // MARK: - Grouping

    @Test("Flattening the groups reproduces the flat order exactly, so the view's sections and the ordering function can never describe two different closets")
    func groupsFlattenBackToTheFlatOrder() {
        let items = tiedCloset
        let flattened = ClosetColorSpectrumOrder.segments(for: items).flatMap(\.items).map(\.id)

        #expect(flattened == ClosetColorSpectrumOrder.ordered(items).map(\.id))
    }

    @Test("Only the groups that hold something are produced, in layout order, so the view never draws a header over nothing")
    func onlyOccupiedGroupsAreProduced() {
        let segments = ClosetColorSpectrumOrder.segments(for: tiedCloset)

        #expect(segments.map(\.band) == [.orange, .blue, .neutral, .noColorRecorded])
        #expect(segments.allSatisfy { !$0.items.isEmpty })
    }

    @Test("A group's swatches are the colours it actually holds, deduplicated and in the garments' own order, rather than one colour invented to stand for the band")
    func groupSwatchesAreTheRealColoursInOrder() throws {
        let items = [
            makeItem(name: "Sky oxford", color: "sky blue"),
            makeItem(name: "Alpine crewneck", color: "navy"),
            makeItem(name: "Zephyr crewneck", color: "navy")
        ]

        let segment = try #require(ClosetColorSpectrumOrder.segments(for: items).first)

        #expect(segment.band == .blue)
        // Navy once, though two garments carry it, and before sky blue
        // because navy is the darker of the two.
        #expect(segment.swatchHexes == [0x1F2A44, 0x8FB4D6])
    }

    @Test("A group of garments with no resolvable colour carries no swatches, because there are none to carry and an invented one would be a lie about the garment")
    func unplaceableGroupsCarryNoSwatches() throws {
        let segment = try #require(ClosetColorSpectrumOrder.segments(for: [makeItem(name: "Field jacket")]).first)

        #expect(segment.band == .noColorRecorded)
        #expect(segment.swatchHexes.isEmpty)
    }
}
