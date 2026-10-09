//
//  KyraOutgoingMessage.swift
//  AstraStyle
//
//  What the user can send Kyra (spec §6.20 "Input: Text, Voice, Photo,
//  Product link, Closet item, Outfit"). Voice is transcribed on-device
//  before it ever reaches this type — Kyra's Edge Function always receives
//  text plus optional structured attachments.
//

import Foundation

public struct KyraOutgoingMessage: Sendable {
    public var text: String
    public var attachments: [Attachment]
    /// Required builder locks; normal chat messages leave this empty.
    public var lockedClosetItemIDs: [UUID]
    public var isOutfitBuilderCompletion: Bool

    public init(
        text: String,
        attachments: [Attachment] = [],
        lockedClosetItemIDs: [UUID] = [],
        isOutfitBuilderCompletion: Bool = false
    ) {
        self.text = text
        self.attachments = attachments
        self.lockedClosetItemIDs = lockedClosetItemIDs
        self.isOutfitBuilderCompletion = isOutfitBuilderCompletion
    }

    public enum Attachment: Sendable {
        case photo(storagePath: String)
        case productLink(URL)
        case closetItem(closetItemID: UUID)
        case outfit(outfitID: UUID)
        case studioInspiration(generationID: UUID)
    }
}
