//
//  StyleMemoriesViewModel.swift
//  AstraStyle
//
//  User-visible memories Kyra uses to personalize advice. Only memories
//  explicitly marked visible are shown; deletion is confirmed in the view
//  and applied through the caller-scoped repository.
//

import Foundation
import Observation

@MainActor
@Observable
public final class StyleMemoriesViewModel {
    public enum State: Sendable {
        case loading
        case loaded([StyleMemory])
        case empty
        case failed(String)
    }

    public private(set) var state: State = .loading
    public private(set) var deletingIDs: Set<UUID> = []
    public var deletionError: String?

    private let kyraRepository: KyraRepository
    private var hasLoaded = false

    public init(kyraRepository: KyraRepository) {
        self.kyraRepository = kyraRepository
    }

    public func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refresh()
    }

    public func refresh() async {
        do {
            // The repository filters server-side too. Keep this client check
            // so an unexpected backend response never exposes hidden notes.
            let fetchedMemories = try await kyraRepository.fetchMemories()
            let memories = fetchedMemories.filter(\.isUserVisible)
            state = memories.isEmpty ? .empty : .loaded(memories)
        } catch let error as AstraError {
            state = .failed(error.message)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func deleteMemory(id: UUID) async {
        guard !deletingIDs.contains(id), case .loaded = state else { return }
        deletingIDs.insert(id)
        defer { deletingIDs.remove(id) }

        do {
            try await kyraRepository.deleteMemory(id: id)
            guard case .loaded(let current) = state else { return }
            let remaining = current.filter { $0.id != id }
            state = remaining.isEmpty ? .empty : .loaded(remaining)
        } catch let error as AstraError {
            deletionError = error.message
        } catch {
            deletionError = error.localizedDescription
        }
    }

    public func clearDeletionError() {
        deletionError = nil
    }
}
