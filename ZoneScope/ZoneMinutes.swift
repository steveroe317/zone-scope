//
//  ZoneMinutes.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation

/// Minutes accumulated in each of the five heart-rate zones.
struct ZoneMinutes {
    var zone1: Double = 0
    var zone2: Double = 0
    var zone3: Double = 0
    var zone4: Double = 0
    var zone5: Double = 0

    var total: Double { zone1 + zone2 + zone3 + zone4 + zone5 }

    subscript(zone: Int) -> Double {
        switch zone {
        case 1: return zone1
        case 2: return zone2
        case 3: return zone3
        case 4: return zone4
        case 5: return zone5
        default: return 0
        }
    }

    static func + (lhs: ZoneMinutes, rhs: ZoneMinutes) -> ZoneMinutes {
        ZoneMinutes(
            zone1: lhs.zone1 + rhs.zone1,
            zone2: lhs.zone2 + rhs.zone2,
            zone3: lhs.zone3 + rhs.zone3,
            zone4: lhs.zone4 + rhs.zone4,
            zone5: lhs.zone5 + rhs.zone5
        )
    }

    static func += (lhs: inout ZoneMinutes, rhs: ZoneMinutes) {
        lhs = lhs + rhs
    }

    /// Every zone's minutes multiplied by `factor` — used to average accumulated sums.
    func scaled(by factor: Double) -> ZoneMinutes {
        ZoneMinutes(
            zone1: zone1 * factor,
            zone2: zone2 * factor,
            zone3: zone3 * factor,
            zone4: zone4 * factor,
            zone5: zone5 * factor
        )
    }

    /// Adds minutes to the given zone (1–5); out-of-range zones are ignored.
    mutating func add(_ minutes: Double, toZone zone: Int) {
        switch zone {
        case 1: zone1 += minutes
        case 2: zone2 += minutes
        case 3: zone3 += minutes
        case 4: zone4 += minutes
        case 5: zone5 += minutes
        default: break
        }
    }
}
