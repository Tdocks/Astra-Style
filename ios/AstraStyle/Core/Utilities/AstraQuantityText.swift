//
//  AstraQuantityText.swift
//  AstraStyle
//
//  Count labels use ordinary words in the source locale. Swift's `^[…]`
//  inflection markers require a String Catalog entry; without one, Foundation
//  returns the marker syntax as visible text.
//

import Foundation

enum AstraQuantityText {
    static func count(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}
