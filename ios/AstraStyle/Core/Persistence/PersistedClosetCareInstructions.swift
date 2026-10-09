//
//  PersistedClosetCareInstructions.swift
//  AstraStyle
//
//  Additive V6 sidecar for optional user-authored care notes. Keeping this
//  separate from PersistedClosetItem avoids mutating any historical schema
//  model while still making notes available in the offline item cache.
//

import Foundation
import SwiftData

@Model
public final class PersistedClosetCareInstructions {
    @Attribute(.unique) public var itemID: UUID
    public var userID: UUID
    public var instructions: String

    public init(itemID: UUID, userID: UUID, instructions: String) {
        self.itemID = itemID
        self.userID = userID
        self.instructions = instructions
    }
}
