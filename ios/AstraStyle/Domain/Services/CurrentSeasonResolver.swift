//
//  CurrentSeasonResolver.swift
//  AstraStyle
//
//  Resolves the meteorological season without sending location coordinates
//  off device. The app transmits only the resulting season tag.
//

import Foundation

public enum CurrentSeasonResolver {
    public static func season(
        at date: Date,
        latitude: Double,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Season {
        let month = calendar.component(.month, from: date)
        let southernHemisphere = latitude < 0

        switch month {
        case 3...5:
            return southernHemisphere ? Season.fall : Season.spring
        case 6...8:
            return southernHemisphere ? Season.winter : Season.summer
        case 9...11:
            return southernHemisphere ? Season.spring : Season.fall
        default:
            return southernHemisphere ? Season.summer : Season.winter
        }
    }
}
