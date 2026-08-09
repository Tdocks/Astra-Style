//
//  ClosetLaundryTests.swift
//  AstraStyleTests
//
//  The laundry alert moved from Home to the Closet. What it names has to be
//  a fact about the WARDROBE, not about whatever the closet screen is
//  currently narrowed to — see `ClosetViewModel.laundryItems`.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Closet laundry alert")
@MainActor
struct ClosetLaundryTests {

    @Test("Only garments actually in the wash are named")
    func onlyLaundryStateLaundryCounts() async {
        let model = makeViewModel(closet: closet())
        await model.onAppear()

        #expect(model.laundryItems.count == 2)
        #expect(model.laundryItems.allSatisfy { $0.laundryState == .laundry })
    }

    @Test("A garment worn once is not in the wash")
    func wornOnceIsNotLaundry() async {
        // `LaundryState` has four cases and only one of them means "in the
        // hamper". Counting `.wornOnce` would tell a man to do a wash he
        // does not need.
        let model = makeViewModel(closet: [item(name: "Tee", state: .wornOnce)])
        await model.onAppear()

        #expect(model.laundryItems.isEmpty)
    }

    @Test("Searching the closet does not change what is in the wash")
    func laundryIsUnaffectedByTheCurrentQuery() async {
        // The alert answers "what is in the hamper", which does not become a
        // different question because he typed "shirt" into the search field.
        let model = makeViewModel(closet: closet())
        await model.onAppear()
        let before = model.laundryItems.count

        model.searchText = "nothing matches this"

        #expect(model.visibleItems.isEmpty)
        #expect(model.laundryItems.count == before)
    }
}

// MARK: - Helpers

@MainActor
private func makeViewModel(closet: [ClosetItem]) -> ClosetViewModel {
    ClosetViewModel(
        closetRepository: MockClosetRepository(items: closet),
        imageURLResolver: MockClosetImageURLResolver()
    )
}

private func closet() -> [ClosetItem] {
    [
        item(name: "Oxford Shirt", state: .laundry),
        item(name: "Chinos", state: .laundry),
        item(name: "Loafers", state: .clean),
        item(name: "Grey Tee", state: .wornOnce)
    ]
}

private func item(name: String, state: LaundryState) -> ClosetItem {
    var made = ClosetItem(
        id: UUID(),
        userID: UUID(),
        name: name,
        category: .top
    )
    made.laundryState = state
    return made
}
