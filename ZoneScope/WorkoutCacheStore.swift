//
//  WorkoutCacheStore.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation
import OSLog

/// Persists the workout cache between launches, so a cold start doesn't have to re-read
/// every workout's heart-rate samples from HealthKit.
///
/// The cache is derived health data, so the file is written with complete protection and
/// excluded from iCloud backup — App Review requires that health data not be stored in
/// iCloud. Every operation is best-effort: the cache is purely an optimization, so any
/// failure falls back to rebuilding from HealthKit rather than surfacing an error.
nonisolated enum WorkoutCacheStore {
    /// Bump when the stored shape or the histogram's meaning changes; a mismatch
    /// discards the file and rebuilds from HealthKit.
    static let schemaVersion = 1

    private struct Payload: Codable {
        let version: Int
        let workouts: [CachedWorkout]
    }

    private static var fileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "ZoneScope", directoryHint: .isDirectory)
            .appending(path: "workout-cache.plist")
    }

    /// Reads the cache, returning an empty dictionary if it's missing, unreadable, or
    /// written by a different schema version.
    static func load() async -> [UUID: CachedWorkout] {
        let signposter = Signposts.healthKit
        let interval = signposter.beginInterval("Load cache", id: signposter.makeSignpostID())
        defer { signposter.endInterval("Load cache", interval) }

        let url = fileURL
        do {
            let data = try Data(contentsOf: url)
            let payload = try PropertyListDecoder().decode(Payload.self, from: data)
            guard payload.version == schemaVersion else {
                Signposts.logger.notice(
                    "Cache schema \(payload.version, privacy: .public) ≠ \(schemaVersion, privacy: .public); rebuilding"
                )
                try? FileManager.default.removeItem(at: url)
                return [:]
            }
            Signposts.logger.notice("""
                Loaded cache: \(payload.workouts.count, privacy: .public) workouts, \
                \(data.count / 1024, privacy: .public) KB
                """)
            return Dictionary(uniqueKeysWithValues: payload.workouts.map { ($0.uuid, $0) })
        } catch CocoaError.fileReadNoSuchFile {
            Signposts.logger.notice("No cache file yet; building from HealthKit")
            return [:]
        } catch {
            Signposts.logger.notice("Cache unreadable (\(error.localizedDescription, privacy: .public)); rebuilding")
            try? FileManager.default.removeItem(at: url)
            return [:]
        }
    }

    /// Writes the cache atomically. Failures are logged and otherwise ignored.
    static func save(_ workouts: [CachedWorkout]) async {
        let signposter = Signposts.healthKit
        let interval = signposter.beginInterval("Save cache", id: signposter.makeSignpostID())
        defer { signposter.endInterval("Save cache", interval) }

        let url = fileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(Payload(version: schemaVersion, workouts: workouts))
            try data.write(to: url, options: [.atomic, .completeFileProtection])

            // Derived health data must not leave the device via backup.
            var excluded = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? excluded.setResourceValues(values)

            Signposts.logger.notice("""
                Saved cache: \(workouts.count, privacy: .public) workouts, \
                \(data.count / 1024, privacy: .public) KB
                """)
        } catch {
            Signposts.logger.notice("Cache save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
