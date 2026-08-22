//
//  HomeBriefEmptyReasonTests.swift
//  AstraStyleTests
//
//  Wear This has to be able to change tomorrow's screen. If every required
//  role is owned but none of it is wearable — typically because it is in
//  the wash — Home used to say `.noOutfitYet` ("add a piece") to a man who
//  already photographed the trousers. That is the same confounding as
//  telling a man with fifteen shirts he owns almost nothing.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Home empty reason: in the wash")
struct HomeBriefEmptyReasonTests {

    @Test("Owned bottoms that are all unwearable are in the wash, not missing")
    func ownedUnwearableRoleIsInTheWash() {
        let data = brief(
            owned: [.top: 3, .bottom: 2, .shoes: 2],
            wearable: [.top: 3, .shoes: 2]
        )
        #expect(data.emptyReason == .inTheWash([.bottom]))
        #expect(data.rolesInTheWash == [.bottom])
        #expect(data.missingRoles.isEmpty)
    }

    @Test("A role he does not own at all is still missing, not in the wash")
    func neverOwnedIsMissingNotInTheWash() {
        let data = brief(
            owned: [.top: 5, .shoes: 2],
            wearable: [.top: 5, .shoes: 2]
        )
        #expect(data.emptyReason == .missingRoles([.bottom]))
        #expect(data.rolesInTheWash.isEmpty)
    }

    @Test("Worn-once garments still count as wearable")
    func wornOnceDoesNotLookLikeTheWash() {
        // The counts here are what the provider would pass after
        // `isWearableToday` started treating `.wornOnce` as wearable.
        let data = brief(
            owned: [.top: 2, .bottom: 2, .shoes: 1],
            wearable: [.top: 2, .bottom: 2, .shoes: 1]
        )
        #expect(data.emptyReason == .noOutfitYet)
        #expect(data.rolesInTheWash.isEmpty)
    }

    @Test("Without wearable counts, do not invent a wash")
    func unknownWearableIsNotAWash() {
        var data = brief(
            owned: [.top: 3, .bottom: 2, .shoes: 2],
            wearable: [:]
        )
        data.wearableRoleCounts = nil
        #expect(data.emptyReason == .noOutfitYet)
        #expect(data.rolesInTheWash.isEmpty)
    }

    @Test("Fewer than five garments still wins over a wash")
    func tooFewItemsBeatsTheWash() {
        let data = brief(
            owned: [.top: 2, .bottom: 1],
            wearable: [.top: 2]
        )
        #expect(data.emptyReason == .tooFewItems(have: 3, need: HomeBriefData.minimumItemsForOutfits))
    }
}

private func brief(
    owned: [ClothingCategory: Int],
    wearable: [ClothingCategory: Int]
) -> HomeBriefData {
    HomeBriefData(
        greetingName: "Marcus",
        weather: nil,
        schedule: nil,
        brief: DailyBrief(id: UUID(), userID: UUID(), briefDate: .now),
        primaryOutfit: nil,
        primaryOutfitItems: [],
        closetRoleCounts: owned,
        wearableRoleCounts: wearable
    )
}
