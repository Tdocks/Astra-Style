//
//  ScanOutfitUnlockEstimatorTests.swift
//  AstraStyleTests
//
//  P3-SCAN-11 Phase-3-era unlock heuristic.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("ScanOutfitUnlockEstimator — complementary partners (P3-SCAN-11)")
struct ScanOutfitUnlockEstimatorTests {
    private let userID = UUID()

    private func item(category: ClothingCategory, name: String = "Piece") -> ClosetItem {
        ClosetItem(id: UUID(), userID: userID, name: name, category: category)
    }

    @Test("A new top unlocks against each bottom, shoe, and outerwear already owned")
    func topUnlocksComplementaryPartners() {
        let closet = [
            item(category: .bottom, name: "Chinos"),
            item(category: .bottom, name: "Jeans"),
            item(category: .shoes, name: "Sneakers"),
            item(category: .top, name: "Other shirt"),
            item(category: .watch, name: "Watch")
        ]
        let added = item(category: .top, name: "Oxford")
        #expect(ScanOutfitUnlockEstimator.newlyUnlockedCount(adding: added, to: closet) == 3)
    }

    @Test("Archived partners do not count")
    func archivedPartnersExcluded() {
        var archived = item(category: .bottom, name: "Old trousers")
        archived.archivedAt = .now
        let closet = [archived, item(category: .shoes, name: "Boots")]
        let added = item(category: .top, name: "Tee")
        #expect(ScanOutfitUnlockEstimator.newlyUnlockedCount(adding: added, to: closet) == 1)
    }

    @Test("An empty complementary set returns zero — never a fabricated positive")
    func emptyClosetReturnsZero() {
        let added = item(category: .top, name: "Lone shirt")
        #expect(ScanOutfitUnlockEstimator.newlyUnlockedCount(adding: added, to: []) == 0)
    }

    @Test("The added item is not counted as its own partner")
    func selfNotCounted() {
        let added = item(category: .top, name: "Self")
        #expect(ScanOutfitUnlockEstimator.newlyUnlockedCount(adding: added, to: [added]) == 0)
    }
}
