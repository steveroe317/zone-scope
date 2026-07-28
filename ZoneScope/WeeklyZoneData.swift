//
//  WeeklyZoneData.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation

/// Zone minutes accumulated within a single calendar week, keyed by that week's start date.
struct WeeklyZoneData: Identifiable {
    let weekStart: Date
    let zoneMinutes: ZoneMinutes

    var id: Date { weekStart }
}
