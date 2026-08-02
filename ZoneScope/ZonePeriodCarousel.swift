//
//  ZonePeriodCarousel.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import SwiftUI

/// A horizontally paged carousel of `ZonePeriodCard`s — one card per day or week —
/// so the user can swipe back through previous periods. Generic over the period
/// type and driven by the shared history series, so the Day and Week modes reuse it.
///
/// The visible range starts at the first period that has data (or the current period
/// if none), trimming leading empty periods; the carousel opens on the current
/// period and swipes back in time.
struct ZonePeriodCarousel<Point: ZoneHistoryPoint, Detail: View>: View {
    /// The full contiguous history, oldest → newest, current period last.
    let points: [Point]
    let component: Calendar.Component
    let maxHeartRate: Double
    let restingHeartRate: Double
    let visibleZones: [Zone]
    /// An optional secondary view for each card (e.g. the week's day chart); `EmptyView`
    /// for the Day carousel.
    private let detail: (Point) -> Detail

    init(
        points: [Point],
        component: Calendar.Component,
        maxHeartRate: Double,
        restingHeartRate: Double,
        visibleZones: [Zone],
        @ViewBuilder detail: @escaping (Point) -> Detail
    ) {
        self.points = points
        self.component = component
        self.maxHeartRate = maxHeartRate
        self.restingHeartRate = restingHeartRate
        self.visibleZones = visibleZones
        self.detail = detail
    }

    /// The cards to show: from the first period with data (or the current period if
    /// there is no data anywhere) through the current period.
    private var cards: ArraySlice<Point> {
        guard let start = points.firstIndex(where: { $0.zoneMinutes.total > 0 }) ?? points.indices.last else {
            return points[points.startIndex..<points.startIndex]
        }
        return points[start...]
    }

    var body: some View {
        let currentID = points.last?.id
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(cards) { point in
                    ZonePeriodCard(
                        point: point,
                        component: component,
                        isCurrent: point.id == currentID,
                        maxHeartRate: maxHeartRate,
                        restingHeartRate: restingHeartRate,
                        visibleZones: visibleZones,
                        detail: detail
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(point.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.trailing)
    }
}

extension ZonePeriodCarousel where Detail == EmptyView {
    /// A carousel whose cards have no secondary view (the summary alone) — used by the
    /// Day carousel.
    init(
        points: [Point],
        component: Calendar.Component,
        maxHeartRate: Double,
        restingHeartRate: Double,
        visibleZones: [Zone]
    ) {
        self.init(
            points: points,
            component: component,
            maxHeartRate: maxHeartRate,
            restingHeartRate: restingHeartRate,
            visibleZones: visibleZones,
            detail: { _ in EmptyView() }
        )
    }
}

#Preview("Week carousel") {
    let calendar = Calendar.current
    let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    let weeks: [WeeklyZoneData] = (0..<6).reversed().map { offset in
        let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek) ?? thisWeek
        // Leave one interior week empty to show a "Rest Week" card.
        let minutes = offset == 2
            ? ZoneMinutes()
            : ZoneMinutes(zone1: Double(60 + offset * 10), zone2: 40, zone3: 25, zone4: 12, zone5: 5)
        return WeeklyZoneData(weekStart: start, zoneMinutes: minutes)
    }
    return ZonePeriodCarousel(
        points: weeks,
        component: .weekOfYear,
        maxHeartRate: 190,
        restingHeartRate: 60,
        visibleZones: Zone.all
    )
}
