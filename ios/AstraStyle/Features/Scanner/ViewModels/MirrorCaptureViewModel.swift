import Foundation
import Observation

@MainActor
@Observable
final class MirrorCaptureViewModel {
    private(set) var imageData: Data?
    private(set) var isSaving = false
    private(set) var savedPath: String?
    private(set) var error: String?
    private(set) var pendingPath: String?
    var hasPermission = false
    private let repository: any ProfileRepository
    private let currentUserID: @Sendable () async -> UUID?

    init(repository: any ProfileRepository, currentUserID: @escaping @Sendable () async -> UUID?) {
        self.repository = repository
        self.currentUserID = currentUserID
    }

    var canSave: Bool { imageData != nil && hasPermission && !isSaving && savedPath == nil }
    var canReplacePhoto: Bool { !isSaving && pendingPath == nil && savedPath == nil }

    func choosePhoto(_ data: Data) {
        guard canReplacePhoto else { return }
        guard let prepared = ReferenceImagePreparation.jpeg(from: data) else {
            error = "That photo couldn't be read. Choose another."
            return
        }
        imageData = prepared
        hasPermission = false
        error = nil
    }

    func save() async {
        guard canSave, let imageData else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            guard let owner = await currentUserID() else { throw AstraError.auth("Sign in to save a private reference photo.") }
            let path: String
            if let pendingPath { path = pendingPath } else {
                path = try await repository.uploadReferenceImage(imageData)
                guard path.hasPrefix("users/\(owner.uuidString.lowercased())/references/") else {
                    throw AstraError.server("The photo couldn't be associated with your account.")
                }
                pendingPath = path
            }
            guard await currentUserID() == owner else { throw AstraError.auth("Your account changed. Reopen capture before saving.") }
            _ = try await repository.associateReferenceImage(path: path, acknowledged: hasPermission)
            savedPath = path
            pendingPath = nil
        } catch {
            self.error = (error as? AstraError)?.message ?? "Couldn't save your reference photo. Try again."
        }
    }
}
