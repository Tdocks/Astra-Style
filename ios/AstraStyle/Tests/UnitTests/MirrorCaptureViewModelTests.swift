import Foundation
import Testing
@testable import AstraStyle

@MainActor
@Suite("Mirror capture")
struct MirrorCaptureViewModelTests {
    private func imageData() throws -> Data {
        let image = try #require(ScannerImageFixtures.solid(width: 32, height: 32, red: 100, green: 100, blue: 100))
        return try #require(ScannerImageFixtures.jpegData(from: image, includeMetadata: false))
    }

    @Test("Saving requires permission and preserves existing body information")
    func privateReferenceSaved() async throws {
        var body = BodyProfile(userID: SampleData.userID)
        body.heightCm = 180
        let repository = MockProfileRepository(bodyProfile: body)
        let model = MirrorCaptureViewModel(repository: repository, currentUserID: { SampleData.userID })
        model.choosePhoto(try imageData())
        await model.save()
        #expect(model.savedPath == nil)
        model.hasPermission = true
        await model.save()
        let path = try #require(model.savedPath)
        let saved = try #require(try await repository.fetchBodyProfile())
        #expect(saved.heightCm == 180)
        #expect(saved.appearance.referenceSelfiePaths == [path])
        #expect(path.hasPrefix("users/\(SampleData.userID.uuidString.lowercased())/references/"))
        await model.save()
        #expect(try await repository.fetchBodyProfile()?.appearance.referenceSelfiePaths.count == 1)
        try await repository.deleteReferenceImage(path: path)
        #expect(try await repository.fetchBodyProfile()?.appearance.referenceSelfiePaths.isEmpty == true)
    }

    @Test("A failed association reuses the uploaded path when retried")
    func failedSaveRetriesSamePhoto() async throws {
        let repository = MockProfileRepository(bodyProfile: BodyProfile(userID: SampleData.userID))
        await repository.failNextBodySaves(1)
        let model = MirrorCaptureViewModel(repository: repository, currentUserID: { SampleData.userID })
        model.choosePhoto(try imageData())
        model.hasPermission = true
        await model.save()
        let pending = try #require(model.pendingPath)
        #expect(model.error != nil)
        #expect(!model.canReplacePhoto)
        await model.save()
        #expect(model.savedPath == pending)
        #expect(model.pendingPath == nil)
    }

    @Test("Invalid photos never become saveable")
    func invalidPhoto() {
        let model = MirrorCaptureViewModel(repository: MockProfileRepository(), currentUserID: { SampleData.userID })
        model.choosePhoto(Data([1, 2, 3]))
        model.hasPermission = true
        #expect(!model.canSave)
        #expect(model.error != nil)
    }
}
