//
//  StudioHomeViewModelTests.swift
//  AstraStyleTests
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Studio tab gallery")
@MainActor
struct StudioHomeViewModelTests {
    @Test("An empty gallery is empty, not a fake generation")
    func emptyGallery() async {
        let model = StudioHomeViewModel(studioRepository: MockStudioRepository())
        await model.onAppear()
        guard case .empty = model.state else {
            Issue.record("expected .empty, got \(model.state)")
            return
        }
    }

    @Test("A saved generation appears on the Studio tab")
    func listsGenerations() async {
        let studio = MockStudioRepository()
        let generation = StudioGeneration(
            id: UUID(),
            userID: SampleData.userID,
            referenceImagePath: "preview/ref.jpg",
            status: .complete,
            resultImagePath: "preview/result.jpg"
        )
        await studio.seed(generation)
        let model = StudioHomeViewModel(studioRepository: studio)
        await model.onAppear()
        guard case .loaded(let items) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(items.map(\.id) == [generation.id])
    }
}
