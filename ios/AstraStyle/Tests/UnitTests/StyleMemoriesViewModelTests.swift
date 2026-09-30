//
//  StyleMemoriesViewModelTests.swift
//  AstraStyleTests
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Style memories privacy controls")
@MainActor
struct StyleMemoriesViewModelTests {
    @Test("Only user-visible notes reach the screen")
    func hidesInternalMemories() async {
        let visible = makeMemory(content: "Prefers neutral knits.")
        let hidden = makeMemory(content: "Low-confidence signal.", isUserVisible: false)
        let repository = StyleMemoryRepositoryStub(memories: [visible, hidden])
        let viewModel = StyleMemoriesViewModel(kyraRepository: repository)

        await viewModel.load()

        guard case .loaded(let memories) = viewModel.state else {
            Issue.record("expected loaded memories")
            return
        }
        #expect(memories == [visible])
    }

    @Test("Deleting a note removes it from the view and repository")
    func deletionRemovesMemory() async throws {
        let memory = makeMemory(content: "Prefers tapered trousers.")
        let repository = StyleMemoryRepositoryStub(memories: [memory])
        let viewModel = StyleMemoriesViewModel(kyraRepository: repository)
        await viewModel.load()

        await viewModel.deleteMemory(id: memory.id)

        guard case .empty = viewModel.state else {
            Issue.record("expected empty after deleting the only memory")
            return
        }
        let storedMemories = try await repository.fetchMemories()
        #expect(storedMemories.isEmpty)
    }

    @Test("A failed deletion keeps the note visible and explains the failure")
    func deletionFailureKeepsMemory() async {
        let memory = makeMemory(content: "Avoids large logos.")
        let repository = StyleMemoryRepositoryStub(memories: [memory], failDeletion: true)
        let viewModel = StyleMemoriesViewModel(kyraRepository: repository)
        await viewModel.load()

        await viewModel.deleteMemory(id: memory.id)

        guard case .loaded(let memories) = viewModel.state else {
            Issue.record("expected failed deletion to keep the memory loaded")
            return
        }
        #expect(memories == [memory])
        #expect(viewModel.deletionError != nil)
    }

    private func makeMemory(content: String, isUserVisible: Bool = true) -> StyleMemory {
        StyleMemory(
            id: UUID(),
            userID: UUID(),
            memoryType: .preference,
            content: content,
            confidence: 0.8,
            isUserVisible: isUserVisible
        )
    }
}

private actor StyleMemoryRepositoryStub: KyraRepository {
    private var memories: [StyleMemory]
    private let failDeletion: Bool

    init(memories: [StyleMemory], failDeletion: Bool = false) {
        self.memories = memories
        self.failDeletion = failDeletion
    }

    func fetchThreads() async throws -> [KyraThread] { [] }
    func fetchMessages(threadID: UUID) async throws -> [KyraMessage] { [] }

    func send(threadID: UUID?, message: KyraOutgoingMessage) async throws -> KyraMessage {
        throw AstraError.unimplemented("Conversation sending is not used in this test.")
    }

    func fetchMemories() async throws -> [StyleMemory] { memories }

    func confirmMemoryProposal(_ proposal: KyraMemoryProposal, sourceMessageID: UUID) async throws -> StyleMemory {
        throw AstraError.unimplemented("Memory confirmation is not used in this test.")
    }

    func deleteMemory(id: UUID) async throws {
        if failDeletion { throw AstraError.network("Couldn't delete this note.") }
        memories.removeAll { $0.id == id }
    }
}
