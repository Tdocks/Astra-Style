//
//  ProfileReferralViewModel.swift
//  AstraStyle
//
//  One-guy referral. Share the code; optionally apply someone else's.
//  Account required. No streaks, no dashboard.
//

import Foundation
import Observation

@MainActor
@Observable
public final class ProfileReferralViewModel {
    public private(set) var code: String?
    public private(set) var referredAlready = false
    public var incomingCode = ""
    public private(set) var note: String?
    public private(set) var isApplying = false

    private let profileRepository: ProfileRepository

    public init(profileRepository: ProfileRepository) {
        self.profileRepository = profileRepository
    }

    public var shareText: String {
        ReferralCopy.shareText(code: code)
    }

    public func onAppear() async {
        guard let profile = try? await profileRepository.fetchCurrentProfile() else { return }
        code = profile.referralCode
        referredAlready = profile.referredBy != nil
    }

    public func applyIncomingCode() async {
        let trimmed = incomingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isApplying, !referredAlready else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            try await profileRepository.applyReferralCode(trimmed)
            referredAlready = true
            note = String(localized: "Code applied.", comment: "Referral code accepted")
        } catch let error as AstraError {
            note = error.message
        } catch {
            note = error.localizedDescription
        }
    }
}

public enum ReferralCopy {
    public static func shareText(code: String?) -> String {
        guard let code, !code.isEmpty else {
            return "Astra Style is for men who hate shopping."
        }
        return "A guy sent you Astra Style. Use code \(code) — it is for men who hate shopping."
    }
}
