//
//  WeekDaySlot.swift
//  AstraStyle
//
//  One day on Home's week strip. A look he can actually wear that morning,
//  not a carousel of cached strangers. Empty means the closet could not
//  cover the day after excluding earlier assignments and laundry.
//

import Foundation

public struct WeekDaySlot: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public var date: Date
    public var outfit: Outfit?
    public var occasionHeadline: String?

    public init(date: Date, outfit: Outfit? = nil, occasionHeadline: String? = nil) {
        self.date = date
        self.outfit = outfit
        self.occasionHeadline = occasionHeadline
    }

    public var hasLook: Bool { outfit != nil }
}
