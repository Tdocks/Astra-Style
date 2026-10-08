//
//  ReferencePhotosViewModelTests.swift
//  AstraStyleTests
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Reference photo privacy controls")
@MainActor
struct ReferencePhotosViewModelTests {
    @Test("Removing a reference photo also removes every saved preview that used it")
    func deletionRemovesRelatedPreviews() async throws {
        let path = referencePath
        var bodyProfile = SampleData.bodyProfile
        bodyProfile.appearance.referenceSelfiePaths = [path]
        let profile = MockProfileRepository(bodyProfile: bodyProfile)
        let studio = MockStudioRepository()
        let generation = StudioGeneration(
            id: UUID(),
            userID: SampleData.userID,
            referenceImagePath: path,
            status: .complete,
            resultImagePath: "preview/result.jpg"
        )
        await studio.seed(generation)

        let model = makeViewModel(profile: profile, studio: studio)
        await model.load()
        await model.deleteReferencePhoto(path: path)

        guard case .empty = model.state else {
            Issue.record("expected no saved reference photos after deletion")
            return
        }
        let savedPaths = try await profile.fetchBodyProfile()?.appearance.referenceSelfiePaths
        let remainingGenerations = try await studio.fetchGenerations()
        #expect(savedPaths?.isEmpty == true)
        #expect(remainingGenerations.isEmpty)
        #expect(model.deletionError == nil)
    }

    @Test("A reference photo cannot be removed while its preview is active")
    func activePreviewBlocksDeletion() async throws {
        let path = referencePath
        var bodyProfile = SampleData.bodyProfile
        bodyProfile.appearance.referenceSelfiePaths = [path]
        let profile = MockProfileRepository(bodyProfile: bodyProfile)
        let studio = MockStudioRepository()
        let generation = StudioGeneration(
            id: UUID(),
            userID: SampleData.userID,
            referenceImagePath: path,
            status: .generating
        )
        await studio.seed(generation)

        let model = makeViewModel(profile: profile, studio: studio)
        await model.load()
        await model.deleteReferencePhoto(path: path)

        guard case .loaded(let photos) = model.state else {
            Issue.record("expected the reference photo to remain available")
            return
        }
        #expect(photos.count == 1)
        #expect(photos[0].isUsedByActivePreview)
        let savedPaths = try await profile.fetchBodyProfile()?.appearance.referenceSelfiePaths
        let remainingGenerations = try await studio.fetchGenerations()
        #expect(savedPaths == [path])
        #expect(remainingGenerations.map(\.id) == [generation.id])
        #expect(model.deletionError != nil)
    }

    private var referencePath: String {
        "users/\(SampleData.userID.uuidString.lowercased())/references/\(UUID().uuidString.lowercased()).jpg"
    }

    @Test("Removing a reference traverses variations and deletes leaves before sources")
    func deletionRemovesTransitiveVariations() async throws {
        let path = referencePath
        var body = SampleData.bodyProfile
        body.appearance.referenceSelfiePaths = [path]
        let profile = MockProfileRepository(bodyProfile: body)
        let studio = MockStudioRepository()
        let root = preview(source: path, result: "root.png")
        let child = preview(source: "root.png", result: "child.png")
        let grandchild = preview(source: "child.png", result: "grandchild.png")
        let unrelated = preview(source: "another-reference.jpg", result: "unrelated.png")
        for generation in [root, child, grandchild, unrelated] { await studio.seed(generation) }
        let model = makeViewModel(profile: profile, studio: studio)
        await model.load()
        guard case .loaded(let photos) = model.state else { Issue.record("missing reference"); return }
        #expect(photos.first?.previewCount == 3)
        await model.deleteReferencePhoto(path: path)
        #expect(model.deletionError == nil)
        #expect(try await studio.fetchGenerations().map(\.id) == [unrelated.id])
        #expect(try await profile.fetchBodyProfile()?.appearance.referenceSelfiePaths.isEmpty == true)
    }

    @Test("An active descendant blocks the entire reference cascade before any deletion")
    func activeVariationBlocksEveryDeletion() async throws {
        let path = referencePath
        var body = SampleData.bodyProfile
        body.appearance.referenceSelfiePaths = [path]
        let profile = MockProfileRepository(bodyProfile: body)
        let studio = MockStudioRepository()
        let root = preview(source: path, result: "root.png")
        let child = preview(source: "root.png", result: nil, status: .generating)
        await studio.seed(root)
        await studio.seed(child)
        let model = makeViewModel(profile: profile, studio: studio)
        await model.load()
        guard case .loaded(let photos) = model.state else { Issue.record("missing reference"); return }
        #expect(photos.first?.isUsedByActivePreview == true)
        await model.deleteReferencePhoto(path: path)
        #expect(model.deletionError != nil)
        #expect(Set(try await studio.fetchGenerations().map(\.id)) == [root.id, child.id])
        #expect(try await profile.fetchBodyProfile()?.appearance.referenceSelfiePaths == [path])
    }

    @Test("Reference traversal spans more than one history page")
    func deletionSpansHistoryPages() async throws {
        let path = referencePath
        var body = SampleData.bodyProfile
        body.appearance.referenceSelfiePaths = [path]
        let profile = MockProfileRepository(bodyProfile: body)
        let studio = MockStudioRepository()
        for index in 0..<105 {
            await studio.seed(preview(source: path, result: "result-\(index).png"))
        }
        let model = makeViewModel(profile: profile, studio: studio)
        await model.load()
        guard case .loaded(let photos) = model.state else { Issue.record("missing reference"); return }
        #expect(photos.first?.previewCount == 105)
        await model.deleteReferencePhoto(path: path)
        #expect(model.deletionError == nil)
        #expect(try await studio.fetchGenerations().isEmpty)
    }

    @Test("An invalid cyclic source chain fails before any preview can be removed")
    func cyclicGraphRefusesDeletion() throws {
        let root = preview(source: "source.jpg", result: "root.png")
        let child = preview(source: "root.png", result: "source.jpg")
        #expect(throws: AstraError.self) {
            try ReferencePhotoPreviewGraph.deletionOrder(sourcePath: "source.jpg", generations: [root, child])
        }
    }

    private func preview(source: String, result: String?, status: StudioGenerationStatus = .complete) -> StudioGeneration {
        StudioGeneration(id: UUID(), userID: SampleData.userID, referenceImagePath: source,
                         status: status, resultImagePath: result)
    }

    private func makeViewModel(
        profile: ProfileRepository,
        studio: StudioRepository
    ) -> ReferencePhotosViewModel {
        ReferencePhotosViewModel(
            profileRepository: profile,
            studioRepository: studio,
            imageURLResolver: MockClosetImageURLResolver()
        )
    }
}
