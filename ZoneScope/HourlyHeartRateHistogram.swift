//
//  HourlyHeartRateHistogram.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation

/// Minutes spent at each whole-BPM heart rate within one clock hour.
///
/// This is deliberately independent of the max/resting heart-rate parameters: zones are
/// derived from it on demand, so a resting-HR drift or a birthday costs a re-bucket
/// rather than re-reading every workout from HealthKit. That independence is what makes
/// the workout cache worth persisting across launches.
struct HourlyHeartRateHistogram: Codable, Sendable {
    let hourStart: Date
    /// Minutes accumulated at each rounded BPM value.
    let minutesByBPM: [Int: Double]

    /// Zone minutes for this hour under the given heart-rate parameters, using the
    /// Heart Rate Reserve (Karvonen) method with boundaries at 60/70/80/90 %.
    ///
    /// This is the single place a heart rate is classified into a zone, so freshly
    /// computed and cache-derived results agree by construction.
    func zoneMinutes(maxHeartRate: Double, restingHeartRate: Double) -> ZoneMinutes {
        var result = ZoneMinutes()
        let reserve = maxHeartRate - restingHeartRate
        guard reserve > 0 else { return result }

        for (bpm, minutes) in minutesByBPM {
            let percentage = (Double(bpm) - restingHeartRate) / reserve
            let zone: Int
            if percentage < 0.60 {
                zone = 1
            } else if percentage < 0.70 {
                zone = 2
            } else if percentage < 0.80 {
                zone = 3
            } else if percentage < 0.90 {
                zone = 4
            } else {
                zone = 5
            }
            result.add(minutes, toZone: zone)
        }
        return result
    }
}
