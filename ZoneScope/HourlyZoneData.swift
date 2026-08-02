//
//  HourlyZoneData.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation

/// Zone minutes accumulated within a single clock hour, keyed by that hour's start
/// date; the element type of a day's per-hour chart.
struct HourlyZoneData: Identifiable {
    let hourStart: Date
    let zoneMinutes: ZoneMinutes

    var id: Date { hourStart }
}

extension HourlyZoneData: ZoneHistoryPoint {
    var date: Date { hourStart }
}
