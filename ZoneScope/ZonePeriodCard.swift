//
//  ZonePeriodCard.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import SwiftUI

/// One page of the Day/Week carousel: a dated header over that period's zone
/// breakdown, or a rest / no-data state. Generic over the period type so the day
/// and week carousels share it, and split out so an iPad layout can reuse it later.
struct ZonePeriodCard<Point: ZoneHistoryPoint, Detail: View>: View {
    let point: Point
    /// The calendar unit this card covers — `.day` or `.weekOfYear`.
    let component: Calendar.Component
    /// Whether this is the current (most recent) period, which shows the ordinary
    /// "no data" state when empty rather than a "rest" state.
    let isCurrent: Bool
    let maxHeartRate: Double
    let restingHeartRate: Double
    let visibleZones: [Zone]
    /// An optional secondary view shown beside the summary (e.g. the week's day chart).
    /// When `EmptyView`, the card shows the summary alone.
    private let detail: (Point) -> Detail

    init(
        point: Point,
        component: Calendar.Component,
        isCurrent: Bool,
        maxHeartRate: Double,
        restingHeartRate: Double,
        visibleZones: [Zone],
        @ViewBuilder detail: @escaping (Point) -> Detail
    ) {
        self.point = point
        self.component = component
        self.isCurrent = isCurrent
        self.maxHeartRate = maxHeartRate
        self.restingHeartRate = restingHeartRate
        self.visibleZones = visibleZones
        self.detail = detail
    }

    /// A relative ("Today", "This Week") or absolute date title for the period.
    private var title: String {
        let calendar = Calendar.zoneScope
        let now = Date()
        if component == .day {
            let today = calendar.startOfDay(for: now)
            let offset = calendar.dateComponents([.day], from: point.date, to: today).day ?? 0
            switch offset {
            case 0: return "Today"
            case 1: return "Yesterday"
            default: return point.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            }
        } else {
            let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let offset = calendar.dateComponents([.weekOfYear], from: point.date, to: currentWeekStart).weekOfYear ?? 0
            switch offset {
            case 0: return "This Week"
            case 1: return "Last Week"
            default:
                let end = calendar.date(byAdding: .day, value: 6, to: point.date) ?? point.date
                let start = point.date.formatted(.dateTime.month(.abbreviated).day())
                let finish = end.formatted(.dateTime.month(.abbreviated).day())
                return "\(start) – \(finish)"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if point.zoneMinutes.total > 0 {
                AdaptiveSplitView {
                    ScrollView {
                        ZoneChartView(
                            zoneMinutes: point.zoneMinutes,
                            maxHeartRate: maxHeartRate,
                            restingHeartRate: restingHeartRate,
                            visibleZones: visibleZones
                        )
                    }
                    .scrollIndicators(.hidden)
                } secondary: {
                    detail(point)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isCurrent {
                NoWorkoutDataView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    component == .day ? "Rest Day" : "Rest Week",
                    systemImage: "moon.zzz",
                    description: Text("No workouts recorded for this \(component == .day ? "day" : "week").")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom)
    }
}

extension ZonePeriodCard where Detail == EmptyView {
    /// A card with no secondary view (the summary alone) — used by the Day carousel.
    init(
        point: Point,
        component: Calendar.Component,
        isCurrent: Bool,
        maxHeartRate: Double,
        restingHeartRate: Double,
        visibleZones: [Zone]
    ) {
        self.init(
            point: point,
            component: component,
            isCurrent: isCurrent,
            maxHeartRate: maxHeartRate,
            restingHeartRate: restingHeartRate,
            visibleZones: visibleZones,
            detail: { _ in EmptyView() }
        )
    }
}

#Preview("Day · data") {
    let calendar = Calendar.zoneScope
    let dayStart = calendar.startOfDay(for: .now)
    let hours: [HourlyZoneData] = (0..<24).compactMap { hour in
        guard let hourStart = calendar.date(byAdding: .hour, value: hour, to: dayStart) else { return nil }
        let minutes = (hour == 7 || hour == 8 || hour == 18)
            ? ZoneMinutes(zone1: 8, zone2: 20, zone3: 18, zone4: 10, zone5: 4)
            : ZoneMinutes()
        return HourlyZoneData(hourStart: hourStart, zoneMinutes: minutes)
    }
    return ZonePeriodCard(
        point: DailyZoneData(
            dayStart: dayStart,
            zoneMinutes: ZoneMinutes(zone1: 32, zone2: 24, zone3: 15, zone4: 8, zone5: 3),
            hours: hours
        ),
        component: .day,
        isCurrent: true,
        maxHeartRate: 190,
        restingHeartRate: 60,
        visibleZones: Zone.all
    ) { day in
        ZoneBarChart(
            points: day.hours,
            visibleZones: Zone.all,
            component: .hour,
            averages: (0..<24).map { hour in
                hour == 7 || hour == 17 || hour == 18
                    ? ZoneMinutes(zone1: 6, zone2: 14, zone3: 10, zone4: 5, zone5: 2)
                    : ZoneMinutes()
            },
            upperBound: 60
        )
    }
}

#Preview("Day · rest day") {
    ZonePeriodCard(
        point: DailyZoneData(
            dayStart: Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now,
            zoneMinutes: ZoneMinutes()
        ),
        component: .day,
        isCurrent: false,
        maxHeartRate: 190,
        restingHeartRate: 60,
        visibleZones: Zone.all
    )
}

#Preview("Week · data") {
    let calendar = Calendar.zoneScope
    let weekStart = calendar.date(byAdding: .weekOfYear, value: -3, to: .now).flatMap {
        calendar.dateInterval(of: .weekOfYear, for: $0)?.start
    } ?? .now
    let days: [DailyZoneData] = (0..<7).compactMap { offset in
        guard let dayStart = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
        let minutes = offset == 3
            ? ZoneMinutes()
            : ZoneMinutes(zone1: Double(20 + offset * 4), zone2: 18, zone3: 12, zone4: 6, zone5: 3)
        return DailyZoneData(dayStart: dayStart, zoneMinutes: minutes)
    }
    return ZonePeriodCard(
        point: WeeklyZoneData(
            weekStart: weekStart,
            zoneMinutes: ZoneMinutes(zone1: 180, zone2: 120, zone3: 70, zone4: 30, zone5: 12),
            days: days
        ),
        component: .weekOfYear,
        isCurrent: false,
        maxHeartRate: 190,
        restingHeartRate: 60,
        visibleZones: Zone.all
    ) { week in
        ZoneBarChart(
            points: week.days,
            visibleZones: Zone.all,
            component: .day,
            averages: [ZoneMinutes](
                repeating: ZoneMinutes(zone1: 24, zone2: 14, zone3: 9, zone4: 5, zone5: 2),
                count: 7
            ),
            upperBound: 90
        )
    }
}
