//
//  AstraAppVersion.swift
//  AstraStyle
//
//  The marketing version and build number as the binary reports them.
//  Dogfood cannot tell builds apart without this on Profile (ADR 0015).
//  Values come from Info.plist (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
//  in ios/project.yml) — never invented App Store Connect facts.
//

import Foundation

public struct AstraAppVersion: Sendable, Equatable {
    public let marketing: String
    public let build: String

    public init(marketing: String, build: String) {
        self.marketing = marketing
        self.build = build
    }

    public static var current: AstraAppVersion {
        AstraAppVersion(
            marketing: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "0.0.0",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                ?? "0"
        )
    }

    /// `1.0.0 (2)` — the form testers can screenshot.
    public var displayLabel: String {
        "\(marketing) (\(build))"
    }
}
