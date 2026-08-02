//
//  TrendGranularity.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation

/// The bar granularity of the Trends time-series: one bar per day or per week.
enum TrendGranularity: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"

    var id: String { rawValue }
}
