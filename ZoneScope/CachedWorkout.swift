//
//  CachedWorkout.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation

/// One workout's heart-rate data reduced to per-hour BPM histograms, plus the identity
/// and dates needed to diff against HealthKit.
///
/// Nothing here depends on the max/resting heart-rate parameters, so an entry stays
/// valid for the life of the workout and can be persisted across launches — reading a
/// workout's heart-rate samples is the expensive part of a cold start.
struct CachedWorkout: Codable, Sendable, Identifiable {
    let uuid: UUID
    let startDate: Date
    let endDate: Date
    let histogram: [HourlyHeartRateHistogram]

    var id: UUID { uuid }
}
