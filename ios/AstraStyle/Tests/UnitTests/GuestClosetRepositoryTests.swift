//
//  GuestClosetRepositoryTests.swift
//  AstraStyleTests
//
//  Phase 1 exit criterion (docs/01-build-roadmap.md): "the client enforces
//  a 10-item local cap without a network call." Every test here calls
//  `GuestClosetRepository`/`GuestAwareClosetRepository` directly — never a
//  view or view model — to prove the cap is enforced at the repository
//  boundary itself (spec §6.2), not merely suggested by a disabled button
//  somewhere.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("GuestClosetRepository — spec §6.2 10-item guest cap")
struct GuestClosetRepositoryTests {

    private func makeItem(userID: UUID = UUID(), name: String) -> ClosetItem {
        ClosetItem(id: UUID(), userID: userID, name: name, category: .top)
    }

    @Test("The 10th item succeeds; the 11th is rejected with a typed error")
    func tenthSucceedsEleventhIsRejected() async throws {
        let guestID = UUID()
        let repository = GuestClosetRepository(store: InMemoryGuestClosetStore(), currentGuestUserID: { guestID })

        for index in 1...GuestLimits.maxClosetItems {
            let created = try await repository.createItem(makeItem(name: "Item \(index)"), images: [])
            #expect(created.userID == guestID)
        }

        let afterTen = try await repository.fetchItems()
        #expect(afterTen.count == GuestLimits.maxClosetItems)

        do {
            _ = try await repository.createItem(makeItem(name: "Item 11"), images: [])
            Issue.record("Expected the 11th guest item to be rejected with GuestClosetError.capReached")
        } catch let error as GuestClosetError {
            #expect(error == .capReached(limit: GuestLimits.maxClosetItems))
        } catch {
            Issue.record("Expected GuestClosetError.capReached, got \(error)")
        }

        // The rejected write didn't corrupt or drop what was already there.
        let afterRejection = try await repository.fetchItems()
        #expect(afterRejection.count == GuestLimits.maxClosetItems)
    }

    @Test("GuestLimits.maxClosetItems is exactly 10, per spec §6.2")
    func capConstantMatchesSpec() {
        #expect(GuestLimits.maxClosetItems == 10)
    }

    @Test("Ownership always comes from the guest session, never a caller-supplied userID")
    func ownershipComesFromGuestSessionNotCaller() async throws {
        let guestID = UUID()
        let spoofedID = UUID()
        let repository = GuestClosetRepository(store: InMemoryGuestClosetStore(), currentGuestUserID: { guestID })

        let created = try await repository.createItem(makeItem(userID: spoofedID, name: "Blazer"), images: [])

        #expect(created.userID == guestID)
        #expect(created.userID != spoofedID)
    }

    @Test("Archiving an item frees a cap slot")
    func archivingFreesCapSlot() async throws {
        let guestID = UUID()
        let repository = GuestClosetRepository(store: InMemoryGuestClosetStore(), currentGuestUserID: { guestID })

        var lastCreatedID = UUID()
        for index in 1...GuestLimits.maxClosetItems {
            lastCreatedID = try await repository.createItem(makeItem(name: "Item \(index)"), images: []).id
        }

        try await repository.archiveItem(id: lastCreatedID)

        let replacement = try await repository.createItem(makeItem(name: "Replacement"), images: [])
        #expect(replacement.name == "Replacement")
    }

    @Test("Scanning is refused locally in guest mode rather than attempted")
    func scanningIsRefusedInGuestMode() async throws {
        let repository = GuestClosetRepository(store: InMemoryGuestClosetStore(), currentGuestUserID: { UUID() })

        await expectThrowsAstraValidationError {
            _ = try await repository.analyzeItem(ClosetItemAnalysisRequest(imageData: Data()))
        }
    }

    @Test("The cap is enforced through the same ClosetRepository AppContainer hands to every screen")
    func capEnforcedThroughGuestAwareRouting() async throws {
        let guestID = UUID()
        let guestRepository = GuestClosetRepository(store: InMemoryGuestClosetStore(), currentGuestUserID: { guestID })
        let liveRepository = MockClosetRepository(items: [])
        let repository = GuestAwareClosetRepository(
            isGuest: { true },
            guestRepository: guestRepository,
            liveRepository: liveRepository
        )

        for index in 1...GuestLimits.maxClosetItems {
            _ = try await repository.createItem(makeItem(name: "Item \(index)"), images: [])
        }

        do {
            _ = try await repository.createItem(makeItem(name: "Item 11"), images: [])
            Issue.record("Expected the 11th guest item to be rejected even through the routing wrapper")
        } catch let error as GuestClosetError {
            #expect(error == .capReached(limit: GuestLimits.maxClosetItems))
        }

        // Confirms guest writes never reached the "live" repository —
        // reinforces "no cloud sync" alongside GuestModeNetworkTests.
        let liveItems = try await liveRepository.fetchItems()
        #expect(liveItems.isEmpty)
    }

    @Test("A non-guest session routes straight through to the live repository")
    func nonGuestRoutesToLiveRepository() async throws {
        // GuestAware itself does not apply the free-tier 30-item cap —
        // `FreeTierCappedClosetRepository` wraps the live path in
        // `AppContainer` (see FreeTierClosetCapTests). This test only
        // proves guest vs live routing.
        let guestRepository = GuestClosetRepository(store: InMemoryGuestClosetStore(), currentGuestUserID: { UUID() })
        let liveRepository = MockClosetRepository(items: [])
        let repository = GuestAwareClosetRepository(
            isGuest: { false },
            guestRepository: guestRepository,
            liveRepository: liveRepository
        )

        for index in 1...(GuestLimits.maxClosetItems + 5) {
            _ = try await repository.createItem(makeItem(name: "Item \(index)"), images: [])
        }

        let items = try await liveRepository.fetchItems()
        #expect(items.count == GuestLimits.maxClosetItems + 5)
    }
}

/// Small shared helper so "expect a validation-category AstraError" reads
/// the same everywhere it's used, without gambling on a `#expect(throws:)`
/// overload for a non-`Equatable`-by-message error value.
func expectThrowsAstraValidationError(_ operation: () async throws -> Void) async {
    do {
        try await operation()
        Issue.record("Expected an AstraError.validation to be thrown")
    } catch let error as AstraError {
        #expect(error.category == .validation)
    } catch {
        Issue.record("Expected AstraError, got \(error)")
    }
}
