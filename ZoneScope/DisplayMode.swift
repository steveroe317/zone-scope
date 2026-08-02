//
//  DisplayMode.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation

/// The mode selected in the main segmented picker: the per-day and per-week card
/// carousels plus the trends time-series.
enum DisplayMode: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case history = "Trends"

    var id: String { rawValue }
}
