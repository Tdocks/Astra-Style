//
//  ClosetItemWearableTests.swift
//  AstraStyleTests
//
//  `isWearableToday` has to agree with the server's `isWearable`. The iOS
//  property used to require `.clean` only, so a shirt marked worn-once —
//  which the engine will still put on a body — looked like laundry on Home
//  and in the outfit builder picker.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("ClosetItem.isWearableToday")
struct ClosetItemWearableTests {

    @Test("Clean and available is wearable")
    func cleanIsWearable() {
        #expect(item(laundry: .clean).isWearableToday)
    }

    @Test("Worn once is still wearable")
    func wornOnceIsWearable() {
        #expect(item(laundry: .wornOnce).isWearableToday)
    }

    @Test("Laundry is not wearable")
    func laundryIsNotWearable() {
        #expect(!item(laundry: .laundry).isWearableToday)
    }

    @Test("Unavailable laundry state is not wearable")
    func unavailableLaundryIsNotWearable() {
        #expect(!item(laundry: .unavailable).isWearableToday)
    }

    @Test("Packed for travel is not wearable even when clean")
    func packedIsNotWearable() {
        var packed = item(laundry: .clean)
        packed.availabilityState = .packedForTravel
        #expect(!packed.isWearableToday)
    }

    @Test("An archived item is not wearable")
    func archivedIsNotWearable() {
        var archived = item(laundry: .clean)
        archived.archivedAt = .now
        #expect(!archived.isWearableToday)
    }
}

private func item(laundry: LaundryState) -> ClosetItem {
    ClosetItem(
        id: UUID(),
        userID: UUID(),
        name: "Oxford",
        category: .top,
        laundryState: laundry
    )
}
