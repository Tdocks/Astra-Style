//
//  OutfitDetailCopyTests.swift
//  AstraStyleTests
//
//  `OutfitDetailCopy` is where the outfit detail screen's "absent is
//  honest, a confounded reading is not" obligation is actually
//  enforceable in code: every case here asserts that a section is built
//  ONLY from what a `ClosetItem` or `Outfit` actually recorded, never
//  padded with something this type invented. Derived from
//  `OutfitDetailViewModel`'s and `OutfitDetailCopy`'s own doc comments,
//  not from the implementation — each test would fail the same way
//  against a differently-written implementation that broke the rule.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("OutfitDetailCopy — spec §6.12 color story / fit notes / share text")
struct OutfitDetailCopyTests {

    private func makeItem(
        name: String = "Knit Polo",
        primaryColor: String? = nil,
        secondaryColors: [String] = [],
        fit: ItemFit? = nil
    ) -> ClosetItem {
        ClosetItem(
            id: UUID(),
            userID: UUID(),
            name: name,
            category: .top,
            primaryColor: primaryColor,
            secondaryColors: secondaryColors,
            fit: fit
        )
    }

    // MARK: - Color story

    @Test("Every recorded primary and secondary colour is kept, in order, duplicates included")
    func colorStoryKeepsEveryRecordedColor() {
        let items = [
            makeItem(primaryColor: "olive", secondaryColors: ["cream"]),
            makeItem(primaryColor: "stone"),
            makeItem(primaryColor: "olive")
        ]

        let names = OutfitDetailCopy.colorStoryNames(for: items)

        #expect(names == ["olive", "cream", "stone", "olive"])
    }

    @Test("A garment with no colour on file contributes nothing — never a placeholder swatch name")
    func colorStorySkipsUnrecordedColors() {
        let items = [makeItem(primaryColor: nil), makeItem(primaryColor: "")]

        let names = OutfitDetailCopy.colorStoryNames(for: items)

        #expect(names.isEmpty)
    }

    // MARK: - Fit notes

    @Test("Only garments with a recorded fit produce a note; the rest are omitted, not shown blank")
    func fitNotesOmitsUnrecordedFits() {
        let noted = makeItem(name: "Chukka Boots", fit: .regular)
        let unnoted = makeItem(name: "Field Watch", fit: nil)

        let notes = OutfitDetailCopy.fitNotes(for: [noted, unnoted])

        #expect(notes.count == 1)
        #expect(notes[0].itemName == "Chukka Boots")
        #expect(notes[0].fit == .regular)
    }

    @Test("Fit notes preserve outfit order")
    func fitNotesPreserveOrder() {
        let first = makeItem(name: "A", fit: .slim)
        let second = makeItem(name: "B", fit: .relaxed)

        let notes = OutfitDetailCopy.fitNotes(for: [first, second])

        #expect(notes.map(\.itemName) == ["A", "B"])
    }

    // MARK: - Occasion line

    @Test("No occasion tags produces no line at all, rather than an empty sentence")
    func occasionLineNilWhenEmpty() {
        #expect(OutfitDetailCopy.occasionLine([]) == nil)
    }

    @Test("Occasion tags join with a middle dot and capitalize, matching the Home hero card's own line")
    func occasionLineFormatsTags() {
        let line = OutfitDetailCopy.occasionLine(["client meeting", "smart casual"])

        #expect(line == "Client Meeting · Smart Casual")
    }

    // MARK: - Share text

    @Test("Share text is the outfit name alone when the server sent no description — nothing is invented to fill the gap")
    func shareTextIsNameOnlyWithNoDescription() {
        let outfit = Outfit(id: UUID(), userID: UUID(), name: "Denim & Oxford", description: nil)

        #expect(OutfitDetailCopy.shareText(for: outfit) == "Denim & Oxford")
    }

    @Test("An empty-string description is treated the same as no description")
    func shareTextTreatsBlankDescriptionAsAbsent() {
        let outfit = Outfit(id: UUID(), userID: UUID(), name: "Denim & Oxford", description: "")

        #expect(OutfitDetailCopy.shareText(for: outfit) == "Denim & Oxford")
    }

    @Test("A real description is appended after the name, exactly as the server sent it")
    func shareTextAppendsRealDescription() {
        let outfit = Outfit(
            id: UUID(),
            userID: UUID(),
            name: "Denim & Oxford",
            description: "A reliable fallback for an unplanned afternoon."
        )

        #expect(OutfitDetailCopy.shareText(for: outfit) == "Denim & Oxford\n\nA reliable fallback for an unplanned afternoon.")
    }
}
