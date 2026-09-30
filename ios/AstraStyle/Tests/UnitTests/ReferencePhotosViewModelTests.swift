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
