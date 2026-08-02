//
//  ZoneHistoryChart.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import SwiftUI
import Charts

/// The trends histogram: stacked zone minutes over time, one bar per `component`
/// (day or week). Shared by both granularities so their bars are the same width.
struct ZoneHistoryChart<Point: ZoneHistoryPoint>: View {
    let points: [Point]
    /// The calendar unit each bar spans — `.day` or `.weekOfYear`.
    let component: Calendar.Component
    let visibleZones: [Zone]

    /// Number of bars shown at once before scrolling is required. Shared across
    /// granularities so daily and weekly bars render at an identical width.
    private let visibleBars = 12

    /// Approximate width a two-line date label ("Mar" / "10") needs to avoid overlap.
    private let minLabelWidth: CGFloat = 30

    @State private var chartWidth: CGFloat = 0

    /// Seconds spanned by one bar, used to size the scrollable visible domain.
    private var secondsPerBar: TimeInterval {
        component == .weekOfYear ? 7 * 24 * 3600 : 24 * 3600
    }

    /// Label every Nth bar so dated labels never overlap at the current width.
    private var labelStride: Int {
        guard chartWidth > 0 else { return 1 }
        let maxLabels = max(2, Int(chartWidth / minLabelWidth))
        return max(1, Int((Double(visibleBars) / Double(maxLabels)).rounded(.up)))
    }

    /// The bar's position in the series, so labels can be strided by index while
    /// each shown label still centers on exactly one bar.
    private func barIndex(for date: Date) -> Int {
        guard let first = points.first?.date else { return 0 }
        return Calendar.zoneScope.dateComponents([component], from: first, to: date).value(for: component) ?? 0
    }

    private func showsLabel(for date: Date) -> Bool {
        let index = barIndex(for: date)
        return index >= 0 && index % labelStride == 0
    }

    /// The label period a bar belongs to; the month name shows on the first labeled
    /// bar of each period. Weekly = calendar month; daily subdivides the month at the
    /// 1st/11th/21st so a month label stays visible within the 12-day window (and, when
    /// labels are thinned, shifts onto the following labeled day rather than vanishing).
    private func labelPeriod(for date: Date) -> (Int, Int, Int) {
        let c = Calendar.zoneScope.dateComponents([.year, .month, .day], from: date)
        let segment = component == .day ? min(2, ((c.day ?? 1) - 1) / 10) : 0
        return (c.year ?? 0, c.month ?? 0, segment)
    }

    /// The month name shows on the first labeled bar of each label period; later
    /// labels in the same period blank the month line to keep the days aligned.
    private func showsMonth(for date: Date) -> Bool {
        guard let previousLabeled = Calendar.zoneScope.date(byAdding: component, value: -labelStride, to: date) else {
            return true
        }
        return labelPeriod(for: previousLabeled) != labelPeriod(for: date)
    }

    /// Anchors the initial scroll position so the most recent bars are visible.
    private var scrollAnchor: Date? {
        guard let last = points.last?.date else { return nil }
        let calendar = Calendar.zoneScope
        return calendar.date(byAdding: component, value: -(visibleBars - 1), to: last) ?? points.first?.date
    }

    var body: some View {
        Chart(points) { point in
            ForEach(visibleZones) { zone in
                BarMark(
                    x: .value("Date", point.date, unit: component),
                    y: .value("Minutes", point.zoneMinutes[zone.number])
                )
                .foregroundStyle(by: .value("Zone", zone.name))
            }
        }
        .chartForegroundStyleScale(
            domain: visibleZones.map(\.name),
            range: visibleZones.map(\.color)
        )
        .chartXVisibleDomain(length: TimeInterval(visibleBars) * secondsPerBar)
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(initialX: scrollAnchor ?? Date())
        .chartXAxis {
            AxisMarks(values: .stride(by: component)) { value in
                AxisGridLine()
                if let date = value.as(Date.self), showsLabel(for: date) {
                    AxisValueLabel(centered: true) {
                        VStack(spacing: 0) {
                            Text(date, format: .dateTime.month(.abbreviated))
                                .foregroundStyle(.primary)
                                .bold()
                                .opacity(showsMonth(for: date) ? 1 : 0)
                            Text(date, format: .dateTime.day())
                        }
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { chartWidth = $0 }
        // Monday-first so weekly bars and axis marks bin to the same weeks as the data.
        .environment(\.calendar, .zoneScope)
        .padding(.horizontal)
    }
}

#Preview("Daily") {
    ZoneHistoryChart(points: DailyZoneData.samples, component: .day, visibleZones: Zone.all)
        .frame(height: 320)
}

#Preview("Weekly") {
    ZoneHistoryChart(points: WeeklyZoneData.samples, component: .weekOfYear, visibleZones: Zone.all)
        .frame(height: 320)
}

#Preview("Subset of zones") {
    ZoneHistoryChart(
        points: WeeklyZoneData.samples,
        component: .weekOfYear,
        visibleZones: Zone.all.filter { $0.number != 1 && $0.number != 3 }
    )
    .frame(height: 320)
}

private extension DailyZoneData {
    /// Ninety days of varied sample data for previews, with some rest days mixed in.
    static var samples: [DailyZoneData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<90).reversed().map { offset in
            let start = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            // Roughly every third day is a rest day with no zone minutes.
            let minutes: ZoneMinutes = offset % 3 == 0
                ? ZoneMinutes()
                : {
                    let scale = Double((offset % 5) + 1)
                    return ZoneMinutes(
                        zone1: 20 + scale * 5,
                        zone2: 15 + scale * 4,
                        zone3: 10 + scale * 3,
                        zone4: 6 + scale * 2,
                        zone5: 3 + scale
                    )
                }()
            return DailyZoneData(dayStart: start, zoneMinutes: minutes)
        }
    }
}

private extension WeeklyZoneData {
    /// Twelve weeks of varied sample data for previews.
    static var samples: [WeeklyZoneData] {
        let calendar = Calendar.current
        let now = Date()
        return (0..<12).reversed().map { offset in
            let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: now) ?? now
            let scale = Double((offset % 4) + 1)
            return WeeklyZoneData(
                weekStart: calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start,
                zoneMinutes: ZoneMinutes(
                    zone1: 120 + scale * 20,
                    zone2: 60 + scale * 15,
                    zone3: 40 + scale * 8,
                    zone4: 20 + scale * 5,
                    zone5: 8 + scale * 2
                )
            )
        }
    }
}
