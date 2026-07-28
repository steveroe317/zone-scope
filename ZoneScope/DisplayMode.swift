//
//  DisplayMode.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation

/// The mode selected in the main segmented picker: two aggregate windows plus the weekly history.
enum DisplayMode: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case history = "History"

    var id: String { rawValue }

    /// The aggregate window this mode maps to, or `nil` for the weekly history view.
    var aggregatePeriod: TimePeriod? {
        switch self {
        case .day: .day
        case .week: .week
        case .history: nil
        }
    }
}
