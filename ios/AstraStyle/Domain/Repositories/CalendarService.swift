//
//  CalendarService.swift
//  AstraStyle
//
//  EventKit-backed occasion awareness (spec §7 "Calendar: when enabling
//  occasion-aware recommendations", §6.8). Maps `EKEvent`s to the domain
//  `Occasion` type so nothing above `Core/Auth`/`Core/Networking` ever
//  imports EventKit directly.
//

import Foundation

public protocol CalendarService: Sendable {
    /// Requests calendar permission only in context (spec §7). Returns
    /// whether permission is now granted.
    func requestAccessIfNeeded() async -> Bool

    /// Upcoming events in the given range, mapped to `Occasion` with
    /// `source == .calendarSynced`. `userID` is stamped onto each mapped
    /// `Occasion` since EventKit itself has no concept of our account
    /// system. If permission was denied, returns an empty array rather
    /// than throwing — spec §21 "Calendar denied: You can still create
    /// occasions manually" implies calendar absence is not an error
    /// state, just an empty one.
    func fetchUpcomingEvents(in range: DateInterval, userID: UUID) async -> [Occasion]
}
