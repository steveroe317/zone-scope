//
//  ZoneHistoryPoint.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation

/// A single dated bucket of zone minutes plotted in the trends histogram. Both the
/// daily and weekly series conform, so one chart view renders either granularity.
///
/// Declared `nonisolated` so the value-type series can cross actor boundaries under
/// the project's main-actor default isolation.
nonisolated protocol ZoneHistoryPoint: Identifiable {
    var date: Date { get }
    var zoneMinutes: ZoneMinutes { get }
}
