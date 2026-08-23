//
//  HomeShareCopy.swift
//  AstraStyle
//
//  Share-sheet text for today's look. Name plus the why-copy the brief
//  already shows — never a follower graph, never an invented sentence.
//

import Foundation

public enum HomeShareCopy {
    /// `name` is the outfit's name. `why` is `kyra_message` or the outfit
    /// description — the same string Home already rendered. Blank why is
    /// treated as absent, matching `OutfitDetailCopy.shareText`.
    public static func shareText(name: String, why: String?) -> String {
        let trimmed = why?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return name }
        return "\(name)\n\n\(trimmed)"
    }
}
