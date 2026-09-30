//
//  PersonalDataExportViewModel.swift
//  AstraStyle
//
//  Creates a private, on-device copy before offering the system share sheet.
//

import Foundation
import Observation

@MainActor
@Observable
public final class PersonalDataExportViewModel {
    public enum State: Equatable {
        case ready
        case exporting
        case available(URL)
        case failed(String)
    }

    public private(set) var state: State = .ready
    private let profileRepository: ProfileRepository

    public init(profileRepository: ProfileRepository) {
        self.profileRepository = profileRepository
    }

    public func createExport() async {
        guard state != .exporting else { return }
        state = .exporting
        do {
            state = .available(try await profileRepository.exportPersonalData())
        } catch let error as AstraError {
            state = .failed(error.message)
        } catch {
            state = .failed(String(localized: "Couldn't create your export. Please try again."))
        }
    }

    public func reset() {
        guard state != .exporting else { return }
        state = .ready
    }
}
