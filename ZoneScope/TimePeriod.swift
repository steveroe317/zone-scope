//
//  TimePeriod.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation

/// A single aggregate window over which zone minutes are summed.
enum TimePeriod: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"

    var id: String { rawValue }

    var startDate: Date {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .day:
            return calendar.startOfDay(for: now)
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        }
    }
}
