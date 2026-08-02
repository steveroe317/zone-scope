//
//  DailyZoneData.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation

/// Zone minutes accumulated within a single calendar day, keyed by that day's start date.
struct DailyZoneData: Identifiable {
    let dayStart: Date
    let zoneMinutes: ZoneMinutes

    var id: Date { dayStart }
}

extension DailyZoneData: ZoneHistoryPoint {
    var date: Date { dayStart }
}
