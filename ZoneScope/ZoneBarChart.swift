//
//  ZoneBarChart.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import SwiftUI
import Charts

/// A compact, non-scrolling stacked bar chart of zone minutes over a fixed set of
/// points — the week card's seven days (`component: .day`) or the day card's 24 hours
/// (`component: .hour`). Kept minimal (no legend; the accompanying summary color-keys
/// the zones) so it fits inside a card. Empty/future points render as zero-height bars
/// under their axis label.
struct ZoneBarChart<Point: ZoneHistoryPoint>: View {
    let points: [Point]
    let visibleZones: [Zone]
    /// The unit each bar spans — `.day` (weekday labels) or `.hour` (hour labels).
    let component: Calendar.Component

    /// Label every Nth bar: all days for a week, every 6th hour for a day (12A/6A/12P/6P).
    private var labelStride: Int {
        component == .hour ? 6 : 1
    }

    /// The bar's position in the series, so labels can be strided by index while each
    /// shown label still centers on exactly one bar.
    private func barIndex(for date: Date) -> Int {
        guard let first = points.first?.date else { return 0 }
        return Calendar.zoneScope.dateComponents([component], from: first, to: date).value(for: component) ?? 0
    }

    private func showsLabel(for date: Date) -> Bool {
        let index = barIndex(for: date)
        return index >= 0 && index % labelStride == 0
    }

    var body: some View {
        Chart(points) { point in
            ForEach(visibleZones) { zone in
                BarMark(
                    x: .value("Time", point.date, unit: component),
                    y: .value("Minutes", point.zoneMinutes[zone.number])
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
            AxisMarks(values: .stride(by: component)) { value in
                if let date = value.as(Date.self), showsLabel(for: date) {
                    AxisValueLabel(centered: true) {
                        if component == .hour {
                            Text(date, format: .dateTime.hour())
                        } else {
                            Text(date, format: .dateTime.weekday(.narrow))
                        }
                    }
                }
            }
        }
        .environment(\.calendar, .zoneScope)
    }
}

#Preview("Week (days)") {
    let calendar = Calendar.zoneScope
    let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    let days: [DailyZoneData] = (0..<7).compactMap { offset in
        guard let dayStart = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
        let minutes = offset >= 5
            ? ZoneMinutes()
            : ZoneMinutes(zone1: Double(20 + offset * 4), zone2: 15, zone3: 10, zone4: 6, zone5: 3)
        return DailyZoneData(dayStart: dayStart, zoneMinutes: minutes)
    }
    return ZoneBarChart(points: days, visibleZones: Zone.all, component: .day)
        .frame(height: 240)
        .padding()
}

#Preview("Day (hours)") {
    let calendar = Calendar.zoneScope
    let dayStart = calendar.startOfDay(for: .now)
    let hours: [HourlyZoneData] = (0..<24).compactMap { hour in
        guard let hourStart = calendar.date(byAdding: .hour, value: hour, to: dayStart) else { return nil }
        // A morning and an evening workout, the rest of the day empty.
        let minutes = (hour == 7 || hour == 8 || hour == 18)
            ? ZoneMinutes(zone1: 8, zone2: 20, zone3: 18, zone4: 10, zone5: 4)
            : ZoneMinutes()
        return HourlyZoneData(hourStart: hourStart, zoneMinutes: minutes)
    }
    return ZoneBarChart(points: hours, visibleZones: Zone.all, component: .hour)
        .frame(height: 240)
        .padding()
}
