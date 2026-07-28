//
//  WeeklyHistoryView.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import SwiftUI
import Charts

struct WeeklyHistoryView: View {
    let weeks: [WeeklyZoneData]
    let visibleZones: [Zone]

    /// Number of weeks shown at once before scrolling is required.
    private let visibleWeeks = 12

    /// Approximate width a dated axis label ("Mar 10") needs to avoid overlap.
    private let minLabelWidth: CGFloat = 64

    @State private var chartWidth: CGFloat = 0

    /// Label every Nth week so dated labels never overlap at the current width.
    private var labelStride: Int {
        guard chartWidth > 0 else { return 1 }
        let maxLabels = max(2, Int(chartWidth / minLabelWidth))
        return max(1, Int((Double(visibleWeeks) / Double(maxLabels)).rounded(.up)))
    }

    /// Anchors the initial scroll position so the most recent weeks are visible.
    private var scrollAnchor: Date? {
        guard let last = weeks.last?.weekStart else { return nil }
        let calendar = Calendar.current
        return calendar.date(byAdding: .weekOfYear, value: -(visibleWeeks - 1), to: last) ?? weeks.first?.weekStart
    }

    var body: some View {
        Chart(weeks) { week in
            ForEach(visibleZones) { zone in
                BarMark(
                    x: .value("Week", week.weekStart, unit: .weekOfYear),
                    y: .value("Minutes", week.zoneMinutes[zone.number])
                )
                .foregroundStyle(by: .value("Zone", zone.name))
            }
        }
        .chartForegroundStyleScale(
            domain: visibleZones.map(\.name),
            range: visibleZones.map(\.color)
        )
        .chartXVisibleDomain(length: TimeInterval(visibleWeeks) * 7 * 24 * 3600)
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(initialX: scrollAnchor ?? Date())
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                AxisGridLine()
            }
            AxisMarks(values: .stride(by: .weekOfYear, count: labelStride)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { chartWidth = $0 }
        .padding(.horizontal)
    }
}

#Preview("All zones") {
    WeeklyHistoryView(weeks: WeeklyZoneData.samples, visibleZones: Zone.all)
        .frame(height: 320)
}

#Preview("Subset of zones") {
    WeeklyHistoryView(
        weeks: WeeklyZoneData.samples,
        visibleZones: Zone.all.filter { $0.number != 1 && $0.number != 3 }
    )
    .frame(height: 320)
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
