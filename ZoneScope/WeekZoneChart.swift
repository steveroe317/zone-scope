//
//  WeekZoneChart.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import SwiftUI
import Charts

/// A compact stacked bar chart of one week's seven days (Monday–Sunday), matching the
/// daily Trends chart's style. Days with no workouts — including a current week's
/// future days — render as empty bars under their weekday label. Kept minimal (no
/// legend; the accompanying summary color-keys the zones) so it fits inside a card.
struct WeekZoneChart: View {
    let days: [DailyZoneData]
    let visibleZones: [Zone]

    var body: some View {
        Chart(days) { day in
            ForEach(visibleZones) { zone in
                BarMark(
                    x: .value("Day", day.dayStart, unit: .day),
                    y: .value("Minutes", day.zoneMinutes[zone.number])
                )
                .foregroundStyle(by: .value("Zone", zone.name))
            }
        }
        .chartForegroundStyleScale(
            domain: visibleZones.map(\.name),
            range: visibleZones.map(\.color)
        )
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel(centered: true) {
                        Text(date, format: .dateTime.weekday(.narrow))
                    }
                }
            }
        }
        .environment(\.calendar, .zoneScope)
    }
}

#Preview {
    let calendar = Calendar.zoneScope
    let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    let days: [DailyZoneData] = (0..<7).compactMap { offset in
        guard let dayStart = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
        // Leave the last two days empty to stand in for future / rest days.
        let minutes = offset >= 5
            ? ZoneMinutes()
            : ZoneMinutes(
                zone1: Double(20 + offset * 4),
                zone2: Double(15 + offset * 3),
                zone3: Double(10 + offset * 2),
                zone4: Double(6 + offset),
                zone5: Double(3 + offset)
            )
        return DailyZoneData(dayStart: dayStart, zoneMinutes: minutes)
    }
    return WeekZoneChart(days: days, visibleZones: Zone.all)
        .frame(height: 240)
        .padding()
}
