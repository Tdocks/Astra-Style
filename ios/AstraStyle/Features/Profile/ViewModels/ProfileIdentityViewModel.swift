//
//  ProfileIdentityViewModel.swift
//  AstraStyle
//
//  Loads the signed-in profile identity and owns private avatar lifecycle.
//

import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ProfileIdentityViewModel {
    enum Phase: Sendable {
        case loading
        case ready(Profile, URL?)
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var isSaving = false
    var notice: String?

    private let profileRepository: ProfileRepository
    private let imageURLResolver: ClosetImageURLResolving

    init(profileRepository: ProfileRepository, imageURLResolver: ClosetImageURLResolving) {
        self.profileRepository = profileRepository
        self.imageURLResolver = imageURLResolver
    }

    func refresh() async {
        notice = nil
        do {
            let profile = try await profileRepository.fetchCurrentProfile()
            let imageURL = await resolveAvatar(for: profile)
            phase = .ready(profile, imageURL)
        } catch let error as AstraError {
            phase = .failed(error.message)
        } catch {
            phase = .failed(String(localized: "Your profile couldn't load. Check your connection and try again.", comment: "Profile identity error"))
        }
    }

    func saveAvatar(_ originalData: Data) async {
        guard !isSaving, case .ready(let currentProfile, _) = phase else { return }
        isSaving = true
        notice = nil
        defer { isSaving = false }

        do {
            let imageData = try Self.optimizedJPEG(from: originalData)
            let newPath = try await profileRepository.uploadProfileAvatar(imageData)
            let updatedProfile: Profile
            do {
                updatedProfile = try await profileRepository.updateAvatarStoragePath(newPath)
            } catch {
                try? await profileRepository.deleteProfileAvatar(path: newPath)
                throw error
            }

            let resolvedAvatar = await resolveAvatar(for: updatedProfile)
            phase = .ready(updatedProfile, resolvedAvatar)
            if resolvedAvatar == nil {
                notice = String(localized: "Your photo is saved, but its preview couldn't load yet.", comment: "Avatar saved but signing or preview failed")
            }
            if let oldPath = currentProfile.avatarStoragePath, oldPath != newPath {
                do {
                    try await profileRepository.deleteProfileAvatar(path: oldPath)
                } catch {
                    notice = String(localized: "Your new photo is saved. The previous copy couldn't be cleared yet.", comment: "Avatar saved with old private file cleanup pending")
                }
            }
        } catch let error as AstraError {
            notice = error.message
        } catch {
            notice = String(localized: "Your photo couldn't be saved. Try again.", comment: "Profile avatar save failure")
        }
    }

    func removeAvatar() async {
        guard !isSaving, case .ready(let currentProfile, _) = phase,
              currentProfile.avatarStoragePath != nil || currentProfile.avatarURL != nil else { return }
        isSaving = true
        notice = nil
        defer { isSaving = false }

        do {
            let updatedProfile = try await profileRepository.updateAvatarStoragePath(nil)
            let oldPath = currentProfile.avatarStoragePath
            phase = .ready(updatedProfile, nil)
            if let oldPath {
                do {
                    try await profileRepository.deleteProfileAvatar(path: oldPath)
                } catch {
                    notice = String(localized: "Your profile photo was removed. Its private file couldn't be cleared yet.", comment: "Avatar removed with old private file cleanup pending")
                }
            }
        } catch let error as AstraError {
            notice = error.message
        } catch {
            notice = String(localized: "Your photo couldn't be removed. Try again.", comment: "Profile avatar removal failure")
        }
    }

    private func resolveAvatar(for profile: Profile) async -> URL? {
        if let path = profile.avatarStoragePath {
            return try? await imageURLResolver.resolve(storagePath: path)
        }
        return profile.avatarURL
    }

    private static func optimizedJPEG(from data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= 25 * 1_024 * 1_024 else {
            throw AstraError.validation("Choose an image smaller than 25 MB.")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 512
                ] as CFDictionary
              ) else {
            throw AstraError.validation("That photo format couldn't be prepared.")
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw AstraError.validation("That photo format couldn't be prepared.")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw AstraError.validation("That photo couldn't be prepared. Choose another image.")
        }
        return output as Data
    }
}
