//
//  LookbookSharingCopy.swift
//  AstraStyle
//
//  Shared copy for the explicit public-look consent shown from Home and
//  Outfit Detail.
//

import Foundation

enum LookbookSharingCopy {
    static var confirmationTitle: String {
        String(localized: "Share this worn look?", comment: "Confirms public lookbook sharing")
    }

    static var confirmationMessage: String {
        String(localized: """
            Other Astra users can see this outfit, its garment names and brands, and the photos \
            attached to those garments. Purchase details, sizes, laundry, and wear history stay \
            private. You can make the look private again anytime.
            """, comment: "Explains what becomes visible before a worn outfit is shared")
    }

    static var confirmTitle: String {
        String(localized: "Share look", comment: "Confirms adding a worn outfit to Discover")
    }

    static var cancelTitle: String {
        String(localized: "Cancel", comment: "Cancels public lookbook sharing")
    }

    static var actionTitle: String {
        String(localized: "Share this worn look", comment: "Home and outfit-detail public lookbook action")
    }
}
