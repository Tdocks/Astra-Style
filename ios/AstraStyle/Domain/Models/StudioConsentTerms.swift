//
//  StudioConsentTerms.swift
//  AstraStyle
//
//  Must stay equal to `CURRENT_STUDIO_CONSENT_TERMS_VERSION` in
//  supabase/functions/studio/schema.ts. A bump on either side without the
//  other is a 400 on every generate.
//

import Foundation

public enum StudioConsentTerms {
    public static let currentVersion = "2026-08-17"
}

/// Wire shape for `POST /studio/generate` `consent`.
public struct StudioConsentAttestation: Encodable, Sendable, Equatable {
    public var acknowledged: Bool
    public var termsVersion: String

    public init(acknowledged: Bool, termsVersion: String = StudioConsentTerms.currentVersion) {
        self.acknowledged = acknowledged
        self.termsVersion = termsVersion
    }

    enum CodingKeys: String, CodingKey {
        case acknowledged
        case termsVersion = "terms_version"
    }
}
