//
//  DailyZoneData.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation

/// Zone minutes accumulated within a single calendar day, keyed by that day's start
/// date, plus that day's 24 hours (00:00–23:00) for the per-hour chart.
struct DailyZoneData: Identifiable {
    let dayStart: Date
    let zoneMinutes: ZoneMinutes
    let hours: [HourlyZoneData]

    var id: Date { dayStart }

    init(dayStart: Date, zoneMinutes: ZoneMinutes, hours: [HourlyZoneData] = []) {
        self.dayStart = dayStart
        self.zoneMinutes = zoneMinutes
        self.hours = hours
    }
}

extension DailyZoneData: ZoneHistoryPoint {
    var date: Date { dayStart }
}
