//
//  TrendsView.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import SwiftUI

/// The Trends tab: a stacked histogram of zone minutes over time at the selected
/// granularity. The Daily · Weekly control that drives `granularity` lives in
/// `ContentView`'s bottom bar.
struct TrendsView: View {
    let dailyHistory: [DailyZoneData]
    let weeklyHistory: [WeeklyZoneData]
    let visibleZones: [Zone]
    let granularity: TrendGranularity

    var body: some View {
        switch granularity {
        case .daily:
            if dailyHistory.contains(where: { $0.zoneMinutes.total > 0 }) {
                ZoneHistoryChart(points: dailyHistory, component: .day, visibleZones: visibleZones)
            } else {
                NoWorkoutDataView()
            }
        case .weekly:
            if weeklyHistory.contains(where: { $0.zoneMinutes.total > 0 }) {
                ZoneHistoryChart(points: weeklyHistory, component: .weekOfYear, visibleZones: visibleZones)
            } else {
                NoWorkoutDataView()
            }
        }
    }
}
