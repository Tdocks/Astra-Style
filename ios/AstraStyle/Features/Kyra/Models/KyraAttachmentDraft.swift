//
//  KyraAttachmentDraft.swift
//  AstraStyle
//
//  An attachment the user has staged in the composer but not yet sent.
//
//  Distinct from `KyraOutgoingMessage.Attachment` because the two live at
//  different moments. The wire attachment for a photo is a STORAGE PATH,
//  which only exists after an upload — and uploading at attach time would
//  mean a photo the user then deletes from the composer has already
//  crossed the network (and would need the `deleteCapturedImage` cleanup
//  dance for a message that was never sent). So the draft holds the raw
//  bytes, and the upload happens inside send, where failure is already a
//  surfaced, retryable state. Closet items and outfits are held as their
//  full rows rather than bare ids so the composer chip can show a real
//  name instead of a UUID.
//

import Foundation

public struct KyraAttachmentDraft: Identifiable, Sendable {
    public enum Payload: Sendable {
        case photo(Data)
        case productLink(URL)
        case closetItem(ClosetItem)
        case outfit(Outfit)
    }

    public let id: UUID
    public var payload: Payload

    public init(id: UUID = UUID(), payload: Payload) {
        self.id = id
        self.payload = payload
    }

    /// What the composer chip says. For a photo there is no honest name to
    /// show, so it says what it is, not a fabricated filename.
    public var label: String {
        switch payload {
        case .photo:
            String(localized: "Photo", comment: "Composer chip for an attached photo")
        case .productLink(let url):
            url.host() ?? url.absoluteString
        case .closetItem(let item):
            item.name
        case .outfit(let outfit):
            outfit.name
        }
    }

    public var iconName: String {
        switch payload {
        case .photo: "photo"
        case .productLink: "link"
        case .closetItem: "tshirt"
        case .outfit: "square.grid.2x2"
        }
    }
}
