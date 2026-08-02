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
struct ZonePeriodCard<Point: ZoneHistoryPoint>: View {
    let point: Point
    /// The calendar unit this card covers — `.day` or `.weekOfYear`.
    let component: Calendar.Component
    /// Whether this is the current (most recent) period, which shows the ordinary
    /// "no data" state when empty rather than a "rest" state.
    let isCurrent: Bool
    let maxHeartRate: Double
    let restingHeartRate: Double
    let visibleZones: [Zone]

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
                ScrollView {
                    ZoneChartView(
                        zoneMinutes: point.zoneMinutes,
                        maxHeartRate: maxHeartRate,
                        restingHeartRate: restingHeartRate,
                        visibleZones: visibleZones
                    )
                }
                .scrollIndicators(.hidden)
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

#Preview("Day · data") {
    ZonePeriodCard(
        point: DailyZoneData(
            dayStart: Calendar.current.startOfDay(for: .now),
            zoneMinutes: ZoneMinutes(zone1: 32, zone2: 24, zone3: 15, zone4: 8, zone5: 3)
        ),
        component: .day,
        isCurrent: true,
        maxHeartRate: 190,
        restingHeartRate: 60,
        visibleZones: Zone.all
    )
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
    ZonePeriodCard(
        point: WeeklyZoneData(
            weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -3, to: .now) ?? .now,
            zoneMinutes: ZoneMinutes(zone1: 180, zone2: 120, zone3: 70, zone4: 30, zone5: 12)
        ),
        component: .weekOfYear,
        isCurrent: false,
        maxHeartRate: 190,
        restingHeartRate: 60,
        visibleZones: Zone.all
    )
}
