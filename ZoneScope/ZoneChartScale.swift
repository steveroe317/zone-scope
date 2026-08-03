//
//  ZoneChartScale.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation

/// Derives the shared y-axis bound for a carousel's card charts, so every card renders
/// at the same vertical scale and its bars stay comparable while paging.
enum ZoneChartScale {
    /// Fallback bound when there is nothing to plot (a `0...0` domain is invalid).
    private static let emptyUpperBound: Double = 30

    /// The y-axis bound for a set of bars: the tallest stack — summed over the visible
    /// zones only — rounded up to a readable step. Rounding keeps the axis labels tidy
    /// and holds the bound steady until a new bar crosses the next step.
    static func upperBound(over minutes: [ZoneMinutes], visibleZones: [Zone]) -> Double {
        let tallest = minutes.reduce(0.0) { current, entry in
            max(current, visibleZones.reduce(0) { $0 + entry[$1.number] })
        }
        guard tallest > 0 else { return emptyUpperBound }

        let step: Double = switch tallest {
        case ..<30:  5
        case ..<60:  15
        case ..<120: 30
        case ..<300: 60
        default:     120
        }
        return (tallest / step).rounded(.up) * step
    }
}
