import Foundation
import Testing
@testable import AstraStyle

@Suite("Offline mutation drain coordinator")
struct OfflineMutationDrainCoordinatorTests {
    @Test("Only online triggers with the active owner drain closet then outfits")
    func validatesOwnerAndOrdersDrains() async {
        let ownerID = UUID()
        let state = DrainCoordinatorState(ownerID: ownerID)
        let coordinator = makeCoordinator(state: state)

        await coordinator.connectivityChanged(isOnline: false)
        await coordinator.sessionChanged(ownerID: nil)
        await coordinator.sessionChanged(ownerID: UUID())
        #expect(await state.events.isEmpty)

        await coordinator.connectivityChanged(isOnline: true)
        #expect(await state.events == ["closet", "outfits"])
    }

    @Test("A session change between repository drains stops before replaying as the new owner")
    func stopsWhenOwnerChanges() async {
        let firstOwner = UUID()
        let replacementOwner = UUID()
        let state = DrainCoordinatorState(ownerID: firstOwner)
        let coordinator = OfflineMutationDrainCoordinator(
            currentOwnerID: { await state.currentOwnerID() },
            drainCloset: { await state.recordClosetAndSwitchOwner(to: replacementOwner) },
            drainOutfits: { await state.record("outfits") }
        )

        await coordinator.sessionChanged(ownerID: firstOwner)

        #expect(await state.events == ["closet"])
        #expect(await state.currentOwnerID() == replacementOwner)
    }

    private func makeCoordinator(state: DrainCoordinatorState) -> OfflineMutationDrainCoordinator {
        OfflineMutationDrainCoordinator(
            currentOwnerID: { await state.currentOwnerID() },
            drainCloset: { await state.record("closet") },
            drainOutfits: { await state.record("outfits") }
        )
    }
}

private actor DrainCoordinatorState {
    private var ownerID: UUID?
    private(set) var events: [String] = []

    init(ownerID: UUID?) {
        self.ownerID = ownerID
    }

    func currentOwnerID() -> UUID? { ownerID }

    func record(_ event: String) {
        events.append(event)
    }

    func recordClosetAndSwitchOwner(to ownerID: UUID) {
        events.append("closet")
        self.ownerID = ownerID
    }
}
