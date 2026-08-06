//
//  Signposts.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import OSLog

/// Instrumentation for the HealthKit read path, so the cost of a cold launch can be
/// measured before and after changes (notably the planned persistent workout cache).
///
/// Two ways to read the results:
///
/// - **Console.app** — connect the device, filter on subsystem `com.roedesigns.test.ZoneScope`,
///   and read the `Startup began` / `Startup completed…` / `Fetched zone data…` summary
///   lines. Every value is logged `.public` so it isn't redacted, and the summaries use
///   `.notice` (the default level) so they appear without enabling "Include Info
///   Messages" and are persisted to disk for later inspection.
/// - **Instruments** — profile the app with a Blank template plus the **os_signpost**
///   instrument, filtered to the same subsystem. The nested intervals show where the
///   time goes: the per-workout `Heart-rate query` spans dominate a cold launch today,
///   since each one is a separate round trip to the HealthKit store.
///
/// Signposts are cheap and safe to leave enabled in Release; disable by swapping the
/// signposter for `OSSignposter(logHandle: .disabled)` if that ever changes.
nonisolated enum Signposts {
    private static let subsystem = "com.roedesigns.test.ZoneScope"

    /// Intervals for the HealthKit fetch path.
    static let healthKit = OSSignposter(subsystem: subsystem, category: "HealthKit")

    /// Summary lines readable in Console without Instruments.
    static let logger = Logger(subsystem: subsystem, category: "HealthKit")

    /// Milliseconds between two clock readings, for the summary lines.
    static func milliseconds(_ start: ContinuousClock.Instant, _ end: ContinuousClock.Instant) -> Double {
        let (seconds, attoseconds) = (end - start).components
        return Double(seconds) * 1000 + Double(attoseconds) / 1_000_000_000_000_000
    }
}
