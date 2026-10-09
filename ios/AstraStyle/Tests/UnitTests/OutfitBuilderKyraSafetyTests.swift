import Foundation
import Testing
@testable import AstraStyle

extension OutfitBuilderViewModelTests {
    @Test("Ask Kyra applies an owned completion to unlocked slots and retains its reason")
    func kyraCompletionPreservesLocksAndReturnsReason() async throws {
        let ownerID = UUID()
        let lockedTop = item(.top, name: "Locked knit", userID: ownerID)
        let oldBottom = item(.bottom, name: "Old trousers", userID: ownerID)
        let newBottom = item(.bottom, name: "Kyra trousers", userID: ownerID)
        let shoes = item(.shoes, name: "Kyra shoes", userID: ownerID)
        let outfitID = UUID()
        let reason = "The textured knit anchors the relaxed tailoring."
        let saved = Outfit(id: outfitID, userID: ownerID, name: "Soft tailoring", description: reason, compatibilityScore: 88, source: .kyraSuggested)
        let rows = [
            OutfitItem(outfitID: outfitID, closetItemID: lockedTop.id, role: .top, sortOrder: 0),
            OutfitItem(outfitID: outfitID, closetItemID: newBottom.id, role: .bottom, sortOrder: 1),
            OutfitItem(outfitID: outfitID, closetItemID: shoes.id, role: .shoes, sortOrder: 2)
        ]
        let repository = StubOutfitRepository()
        await repository.setLoadedOutfit(saved, items: rows)
        let reply = KyraMessage(
            id: UUID(), threadID: UUID(), role: .assistant, content: reason,
            structuredPayload: KyraStructuredResponse(message: reason, intent: .dailyOutfit, cards: [.outfit(outfitID: outfitID)], confidence: 1)
        )
        let kyra = StubKyraRepository(reply: reply)
        let (viewModel, _) = makeViewModel(
            closet: [lockedTop, oldBottom, newBottom, shoes], repository: repository,
            kyraRepository: kyra, ownerID: ownerID
        )
        await viewModel.onAppear()
        viewModel.selectItem(lockedTop, for: .top)
        viewModel.selectItem(oldBottom, for: .bottom)
        viewModel.toggleLock(for: .top)

        await viewModel.askKyraToFinish()

        #expect(viewModel.slots.first(where: { $0.category == .top })?.item?.id == lockedTop.id)
        #expect(viewModel.slots.first(where: { $0.category == .top })?.isLocked == true)
        #expect(viewModel.slots.first(where: { $0.category == .bottom })?.item?.id == newBottom.id)
        #expect(viewModel.slots.first(where: { $0.category == .shoes })?.item?.id == shoes.id)
        #expect(viewModel.kyraReason == reason)
        let sent = await kyra.lastMessage
        #expect(sent?.lockedClosetItemIDs == [lockedTop.id])
        #expect(sent?.isOutfitBuilderCompletion == true)
    }

    @Test("Kyra completion from an existing outfit saves back to its original identity")
    func kyraEditKeepsOriginalOutfitIdentity() async throws {
        let owner = UUID()
        let top = item(.top, name: "Original top", userID: owner)
        let bottom = item(.bottom, name: "Original bottom", userID: owner)
        let shoes = item(.shoes, name: "Original shoes", userID: owner)
        let replacementBottom = item(.bottom, name: "Kyra bottom", userID: owner)
        let originalID = UUID()
        let suggestionID = UUID()
        let original = Outfit(id: originalID, userID: owner, name: "Saved outfit", description: "Original description")
        let suggestion = Outfit(id: suggestionID, userID: owner, name: "Updated outfit", description: "A fresh combination")
        let originalRows = [
            OutfitItem(outfitID: originalID, closetItemID: top.id, role: .top, sortOrder: 0),
            OutfitItem(outfitID: originalID, closetItemID: bottom.id, role: .bottom, sortOrder: 1),
            OutfitItem(outfitID: originalID, closetItemID: shoes.id, role: .shoes, sortOrder: 2)
        ]
        let suggestionRows = [
            OutfitItem(outfitID: suggestionID, closetItemID: top.id, role: .top, sortOrder: 0),
            OutfitItem(outfitID: suggestionID, closetItemID: replacementBottom.id, role: .bottom, sortOrder: 1),
            OutfitItem(outfitID: suggestionID, closetItemID: shoes.id, role: .shoes, sortOrder: 2)
        ]
        let repository = StubOutfitRepository()
        await repository.setLoadedOutfit(original, items: originalRows)
        await repository.setOutfit(suggestion, items: suggestionRows)
        let reply = makeKyraReply(outfitID: suggestionID, message: suggestion.description ?? "")
        let (viewModel, _) = makeViewModel(
            closet: [top, bottom, shoes, replacementBottom], repository: repository,
            startingOutfitID: originalID,
            kyraRepository: StubKyraRepository(reply: reply), ownerID: owner
        )
        await viewModel.onAppear()
        await viewModel.askKyraToFinish()

        #expect(viewModel.slots.first(where: { $0.category == .bottom })?.item?.id == replacementBottom.id)
        #expect(viewModel.backingOutfitID == originalID)
        #expect(viewModel.savedOutfit?.id == originalID)
        #expect(viewModel.kyraReason == suggestion.description)
        viewModel.selectItem(bottom, for: .bottom)
        #expect(viewModel.kyraReason == nil)
        await viewModel.save()
        #expect(await repository.lastReplacedOutfitID == originalID)
    }

    func makeKyraReply(outfitID: UUID?, message: String = "Completed.") -> KyraMessage {
        let cards: [KyraCard] = outfitID.map { [.outfit(outfitID: $0)] } ?? []
        return KyraMessage(
            id: UUID(), threadID: UUID(), role: .assistant, content: message,
            structuredPayload: KyraStructuredResponse(message: message, intent: .dailyOutfit, cards: cards, confidence: 1)
        )
    }

    @Test("Kyra transport failure leaves the canvas unchanged and exposes a retryable error")
    func kyraFailureDoesNotMutateCanvas() async throws {
        let owner = UUID()
        let top = item(.top, name: "Keep current", userID: owner)
        let repository = StubOutfitRepository()
        let kyra = StubKyraRepository(reply: makeKyraReply(outfitID: nil), sendError: .network("Offline"))
        let (viewModel, _) = makeViewModel(closet: [top], repository: repository, kyraRepository: kyra, ownerID: owner)
        await viewModel.onAppear()
        viewModel.selectItem(top, for: .top)

        await viewModel.askKyraToFinish()

        #expect(viewModel.slots.first(where: { $0.category == .top })?.item?.id == top.id)
        #expect(viewModel.kyraReason == nil)
        #expect(viewModel.actionError?.message == "Offline")
        #expect(viewModel.askKyraState == .idle)
    }

    @Test("A reply without an outfit card never fetches or mutates the canvas")
    func kyraMissingCardDoesNotMutateCanvas() async throws {
        let owner = UUID()
        let top = item(.top, name: "Keep current", userID: owner)
        let kyra = StubKyraRepository(reply: makeKyraReply(outfitID: nil))
        let (viewModel, _) = makeViewModel(closet: [top], kyraRepository: kyra, ownerID: owner)
        await viewModel.onAppear()
        viewModel.selectItem(top, for: .top)

        await viewModel.askKyraToFinish()

        #expect(viewModel.slots.first(where: { $0.category == .top })?.item?.id == top.id)
        #expect(viewModel.actionError?.message.contains("did not return") == true)
    }

    @Test("An account switch while Kyra is responding rejects the completion")
    func kyraAccountSwitchRejectsResult() async throws {
        let owner = UUID()
        let peer = UUID()
        let top = item(.top, name: "Keep current", userID: owner)
        let completedTop = item(.top, name: "Peer completion", userID: owner)
        let bottom = item(.bottom, name: "Peer trousers", userID: owner)
        let shoes = item(.shoes, name: "Peer shoes", userID: owner)
        let outfitID = UUID()
        let outfit = Outfit(id: outfitID, userID: owner, name: "Should not load", description: "Reason")
        let rows = [
            OutfitItem(outfitID: outfitID, closetItemID: completedTop.id, role: .top, sortOrder: 0),
            OutfitItem(outfitID: outfitID, closetItemID: bottom.id, role: .bottom, sortOrder: 1),
            OutfitItem(outfitID: outfitID, closetItemID: shoes.id, role: .shoes, sortOrder: 2)
        ]
        let repository = StubOutfitRepository()
        await repository.setLoadedOutfit(outfit, items: rows)
        let ownerState = OwnerState(owner)
        let kyra = StubKyraRepository(reply: makeKyraReply(outfitID: outfitID), onSend: {
            await ownerState.switchTo(peer)
        })
        let (viewModel, _) = makeViewModel(
            closet: [top, completedTop, bottom, shoes], repository: repository, kyraRepository: kyra,
            ownerProvider: { await ownerState.current() }
        )
        await viewModel.onAppear()
        viewModel.selectItem(top, for: .top)

        await viewModel.askKyraToFinish()

        #expect(viewModel.slots.first(where: { $0.category == .top })?.item?.id == top.id)
        #expect(viewModel.savedOutfit == nil)
        #expect(viewModel.actionError?.category == .auth)
        #expect(await kyra.lastExpectedOwnerID == owner)
    }

    @Test("Concurrent Ask Kyra taps send one owner-scoped request")
    func concurrentAskKyraSendsOnce() async throws {
        let owner = UUID()
        let top = item(.top, name: "Owned top", userID: owner)
        let kyra = StubKyraRepository(
            reply: makeKyraReply(outfitID: nil),
            onSend: { try? await Task.sleep(for: .milliseconds(100)) }
        )
        let (viewModel, _) = makeViewModel(closet: [top], kyraRepository: kyra, ownerID: owner)
        await viewModel.onAppear()
        viewModel.selectItem(top, for: .top)

        let firstRequest = Task { await viewModel.askKyraToFinish() }
        try await Task.sleep(for: .milliseconds(10))
        await viewModel.askKyraToFinish()
        await firstRequest.value

        #expect(await kyra.sendCount == 1)
        #expect(await kyra.lastExpectedOwnerID == owner)
    }

    @Test("Archived outfit, archived garment, product-card item, and duplicate item rows fail validation")
    func kyraRejectsArchivedOrMalformedCompletion() async throws {
        let owner = UUID()
        let currentTop = item(.top, name: "Keep current", userID: owner)
        let archivedTop = ClosetItem(id: UUID(), userID: owner, name: "Archived", category: .top, archivedAt: .now)
        let bottom = item(.bottom, name: "Trousers", userID: owner)
        let shoes = item(.shoes, name: "Shoes", userID: owner)
        let foreignOwner = UUID()
        let outfitID = UUID()
        let badOutfit = Outfit(id: outfitID, userID: foreignOwner, name: "Archived outfit", description: "Reason", archivedAt: .now)
        let repository = StubOutfitRepository()
        await repository.setLoadedOutfit(badOutfit, items: [
            OutfitItem(outfitID: outfitID, closetItemID: archivedTop.id, role: .top, sortOrder: 0),
            OutfitItem(outfitID: outfitID, closetItemID: bottom.id, role: .bottom, sortOrder: 1),
            OutfitItem(outfitID: outfitID, closetItemID: shoes.id, role: .shoes, sortOrder: 2)
        ])
        let kyra = StubKyraRepository(reply: makeKyraReply(outfitID: outfitID))
        let (viewModel, _) = makeViewModel(
            closet: [currentTop, archivedTop, bottom, shoes], repository: repository,
            kyraRepository: kyra, ownerID: owner
        )
        await viewModel.onAppear()
        viewModel.selectItem(currentTop, for: .top)

        await viewModel.askKyraToFinish()

        #expect(viewModel.slots.first(where: { $0.category == .top })?.item?.id == currentTop.id)
        #expect(viewModel.savedOutfit == nil)
        #expect(viewModel.actionError?.category == .auth)
    }
    @Test("An archived outfit is not accepted as a completion target")
    func kyraRejectsArchivedOutfit() async throws {
        let owner = UUID()
        let top = item(.top, name: "Current top", userID: owner)
        let bottom = item(.bottom, name: "Owned bottom", userID: owner)
        let shoes = item(.shoes, name: "Owned shoes", userID: owner)
        let outfitID = UUID()
        let outfit = Outfit(id: outfitID, userID: owner, name: "Archived look", description: "Reason", archivedAt: .now)
        let repository = StubOutfitRepository()
        await repository.setLoadedOutfit(outfit, items: [
            OutfitItem(outfitID: outfitID, closetItemID: top.id, role: .top, sortOrder: 0),
            OutfitItem(outfitID: outfitID, closetItemID: bottom.id, role: .bottom, sortOrder: 1),
            OutfitItem(outfitID: outfitID, closetItemID: shoes.id, role: .shoes, sortOrder: 2)
        ])
        let (viewModel, _) = makeViewModel(
            closet: [top, bottom, shoes], repository: repository,
            kyraRepository: StubKyraRepository(reply: makeKyraReply(outfitID: outfitID)), ownerID: owner
        )
        await viewModel.onAppear()
        viewModel.selectItem(top, for: .top)

        await viewModel.askKyraToFinish()

        #expect(viewModel.slots.first(where: { $0.category == .top })?.item?.id == top.id)
        #expect(viewModel.savedOutfit == nil)
        #expect(viewModel.actionError?.category == .validation)
    }

    @Test("An archived closet item in a Kyra card is rejected")
    func kyraRejectsArchivedClosetItem() async throws {
        let owner = UUID()
        let top = item(.top, name: "Current top", userID: owner)
        let archived = ClosetItem(id: UUID(), userID: owner, name: "Archived bottom", category: .bottom, archivedAt: .now)
        let shoes = item(.shoes, name: "Owned shoes", userID: owner)
        let outfitID = UUID()
        let repository = StubOutfitRepository()
        await repository.setLoadedOutfit(Outfit(id: outfitID, userID: owner, name: "Bad ref", description: "Reason"), items: [
            OutfitItem(outfitID: outfitID, closetItemID: top.id, role: .top, sortOrder: 0),
            OutfitItem(outfitID: outfitID, closetItemID: archived.id, role: .bottom, sortOrder: 1),
            OutfitItem(outfitID: outfitID, closetItemID: shoes.id, role: .shoes, sortOrder: 2)
        ])
        let (viewModel, _) = makeViewModel(
            closet: [top, archived, shoes], repository: repository,
            kyraRepository: StubKyraRepository(reply: makeKyraReply(outfitID: outfitID)), ownerID: owner
        )
        await viewModel.onAppear()
        viewModel.selectItem(top, for: .top)

        await viewModel.askKyraToFinish()

        #expect(viewModel.slots.first(where: { $0.category == .top })?.item?.id == top.id)
        #expect(viewModel.savedOutfit == nil)
        #expect(viewModel.actionError?.category == .validation)
    }

    @Test("A card containing a product candidate is rejected")
    func kyraRejectsProductCandidateRow() async throws {
        let owner = UUID()
        let top = item(.top, name: "Current top", userID: owner)
        let bottom = item(.bottom, name: "Owned bottom", userID: owner)
        let shoes = item(.shoes, name: "Owned shoes", userID: owner)
        let outfitID = UUID()
        let repository = StubOutfitRepository()
        await repository.setLoadedOutfit(Outfit(id: outfitID, userID: owner, name: "Incomplete", description: "Reason"), items: [
            OutfitItem(outfitID: outfitID, closetItemID: top.id, role: .top, sortOrder: 0),
            OutfitItem(outfitID: outfitID, closetItemID: bottom.id, role: .bottom, sortOrder: 1),
            OutfitItem(outfitID: outfitID, productCandidateID: UUID(), role: .shoes, sortOrder: 2)
        ])
        let (viewModel, _) = makeViewModel(
            closet: [top, bottom, shoes], repository: repository,
            kyraRepository: StubKyraRepository(reply: makeKyraReply(outfitID: outfitID)), ownerID: owner
        )
        await viewModel.onAppear()
        viewModel.selectItem(top, for: .top)

        await viewModel.askKyraToFinish()

        #expect(viewModel.savedOutfit == nil)
        #expect(viewModel.actionError?.category == .validation)
    }

    @Test("Duplicate references in a Kyra card are rejected")
    func kyraRejectsDuplicateItemRows() async throws {
        let owner = UUID()
        let top = item(.top, name: "Current top", userID: owner)
        let bottom = item(.bottom, name: "Owned bottom", userID: owner)
        let shoes = item(.shoes, name: "Owned shoes", userID: owner)
        let outfitID = UUID()
        let repository = StubOutfitRepository()
        await repository.setLoadedOutfit(Outfit(id: outfitID, userID: owner, name: "Duplicate", description: "Reason"), items: [
            OutfitItem(outfitID: outfitID, closetItemID: top.id, role: .top, sortOrder: 0),
            OutfitItem(outfitID: outfitID, closetItemID: bottom.id, role: .bottom, sortOrder: 1),
            OutfitItem(outfitID: outfitID, closetItemID: bottom.id, role: .bottom, sortOrder: 2),
            OutfitItem(outfitID: outfitID, closetItemID: shoes.id, role: .shoes, sortOrder: 3)
        ])
        let (viewModel, _) = makeViewModel(
            closet: [top, bottom, shoes], repository: repository,
            kyraRepository: StubKyraRepository(reply: makeKyraReply(outfitID: outfitID)), ownerID: owner
        )
        await viewModel.onAppear()
        viewModel.selectItem(top, for: .top)

        await viewModel.askKyraToFinish()

        #expect(viewModel.savedOutfit == nil)
        #expect(viewModel.actionError?.category == .validation)
    }

}
