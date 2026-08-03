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
    /// Typical zone minutes for each bar, drawn behind it as a faint "high water mark"
    /// reference. Parallel to `points`; empty to draw no background.
    var averages: [ZoneMinutes] = []
    /// The y-axis maximum, supplied by the caller so every card in a carousel shares one
    /// scale rather than each chart auto-scaling to its own bars. See `ZoneChartScale`.
    let upperBound: Double

    /// Label every Nth bar: all days for a week, every 6th hour for a day (12A/6A/12P/6P).
    private var labelStride: Int {
        component == .hour ? 6 : 1
    }

    private func average(at index: Int) -> ZoneMinutes {
        averages.indices.contains(index) ? averages[index] : ZoneMinutes()
    }

    /// The zone's slice of a stacked background bar: cumulative offsets across the
    /// visible zones, so background segments stack among themselves.
    private func bounds(for zone: Zone, in minutes: ZoneMinutes) -> (start: Double, end: Double) {
        var start = 0.0
        for visible in visibleZones {
            let value = minutes[visible.number]
            if visible.number == zone.number { return (start, start + value) }
            start += value
        }
        return (start, start)
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
        Chart {
            ForEach(points.enumerated(), id: \.element.id) { index, point in
                // The average, drawn first so the actual bar covers it. Explicit y
                // ranges keep it out of the foreground's automatic stacking.
                let typical = average(at: index)
                ForEach(visibleZones) { zone in
                    let span = bounds(for: zone, in: typical)
                    BarMark(
                        x: .value("Time", point.date, unit: component),
                        yStart: .value("Minutes", span.start),
                        yEnd: .value("Minutes", span.end)
                    )
                    .foregroundStyle(zone.color.opacity(0.15))
                }
                ForEach(visibleZones) { zone in
                    BarMark(
                        x: .value("Time", point.date, unit: component),
                        y: .value("Minutes", point.zoneMinutes[zone.number])
                    )
                    .foregroundStyle(by: .value("Zone", zone.name))
                }
            }
        }
        .chartForegroundStyleScale(
            domain: visibleZones.map(\.name),
            range: visibleZones.map(\.color)
        )
        .chartYScale(domain: 0...upperBound)
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
    // A flat "typical" week, so some days land above it and some below.
    let averages = [ZoneMinutes](
        repeating: ZoneMinutes(zone1: 24, zone2: 14, zone3: 9, zone4: 5, zone5: 2),
        count: 7
    )
    return ZoneBarChart(
        points: days,
        visibleZones: Zone.all,
        component: .day,
        averages: averages,
        upperBound: 90
    )
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
    // Typically a light morning and a bigger evening session on this weekday.
    let averages: [ZoneMinutes] = (0..<24).map { hour in
        switch hour {
        case 7:  return ZoneMinutes(zone1: 6, zone2: 10, zone3: 6, zone4: 2, zone5: 1)
        case 17: return ZoneMinutes(zone1: 5, zone2: 12, zone3: 9, zone4: 4, zone5: 1)
        case 18: return ZoneMinutes(zone1: 7, zone2: 16, zone3: 12, zone4: 6, zone5: 2)
        default: return ZoneMinutes()
        }
    }
    return ZoneBarChart(
        points: hours,
        visibleZones: Zone.all,
        component: .hour,
        averages: averages,
        upperBound: 60
    )
    .frame(height: 240)
    .padding()
}
