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

    public init(text: String, attachments: [Attachment] = []) {
        self.text = text
        self.attachments = attachments
    }

    public enum Attachment: Sendable {
        case photo(storagePath: String)
        case productLink(URL)
        case closetItem(closetItemID: UUID)
        case outfit(outfitID: UUID)
    }
}
