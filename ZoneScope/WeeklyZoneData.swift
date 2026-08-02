//
//  WeeklyZoneData.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation

/// Zone minutes accumulated within a single calendar week, keyed by that week's start
/// date, plus that week's seven days (Monday–Sunday) for the per-day chart.
struct WeeklyZoneData: Identifiable {
    let weekStart: Date
    let zoneMinutes: ZoneMinutes
    let days: [DailyZoneData]

    var id: Date { weekStart }

    init(weekStart: Date, zoneMinutes: ZoneMinutes, days: [DailyZoneData] = []) {
        self.weekStart = weekStart
        self.zoneMinutes = zoneMinutes
        self.days = days
    }
}

extension WeeklyZoneData: ZoneHistoryPoint {
    var date: Date { weekStart }
}
