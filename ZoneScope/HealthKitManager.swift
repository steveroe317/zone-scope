//
//  HealthKitManager.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation
import HealthKit
import OSLog

/// A cached workout with its zone minutes resolved against the current heart-rate
/// parameters. Rebuilt on each recompute, which is what lets a max/resting HR change
/// cost a re-bucket instead of re-reading every workout from HealthKit.
private struct ResolvedWorkout {
    let startDate: Date
    let zoneMinutes: ZoneMinutes
    /// Zone minutes bucketed by the clock hour they fell in, keyed by that hour's start
    /// date. Feeds the day card's per-hour chart.
    let hourlyZoneMinutes: [Date: ZoneMinutes]
}

enum AccessPhase {
    case determining
    case needsAuthorization
    case ready
}

@MainActor @Observable
final class HealthKitManager {
    var accessPhase: AccessPhase = .determining
    var isLoading = false
    var weeklyHistory: [WeeklyZoneData] = []
    var dailyHistory: [DailyZoneData] = []
    /// Average zone minutes per weekday over the averaging window, Monday-first.
    var weekdayAverages: [ZoneMinutes] = Array(repeating: ZoneMinutes(), count: 7)
    /// Average zone minutes per hour for each weekday over the averaging window,
    /// indexed `[weekday (Monday-first)][hour]`.
    var hourlyAveragesByWeekday: [[ZoneMinutes]] = Array(
        repeating: Array(repeating: ZoneMinutes(), count: 24),
        count: 7
    )
    private(set) var lastFetchDate: Date?

    /// Whether there is anything to render — true as soon as the persisted cache loads,
    /// so a cached launch paints immediately instead of showing the loading spinner.
    var hasData: Bool {
        !dailyHistory.isEmpty || !weeklyHistory.isEmpty
    }

    private let healthStore = HKHealthStore()
    private var workoutObserverQuery: HKObserverQuery?
    var maxHeartRate: Double = 190
    var restingHeartRate: Double = 60

    private var workoutCache: [UUID: CachedWorkout] = [:]

    /// How many heart-rate queries may be in flight at once. Each spends most of its
    /// time waiting on HealthKit, so overlapping them is where the speed-up comes from.
    private let maxConcurrentQueries = 6

    /// Number of weeks of history fetched and shown in the weekly view.
    static let historyWeeks = 52

    /// Number of days shown in the daily trends view.
    static let historyDays = 90

    /// Number of weeks averaged for the cards' "high water mark" chart backgrounds.
    static let averageWeeks = 12

    /// Start of the earliest week included in the fetch/history window.
    private var historyStartDate: Date {
        let calendar = Calendar.zoneScope
        let earliest = calendar.date(byAdding: .weekOfYear, value: -(Self.historyWeeks - 1), to: Date()) ?? Date()
        return calendar.dateInterval(of: .weekOfYear, for: earliest)?.start ?? earliest
    }

    /// Start of the earliest day included in the daily trends window.
    private var dailyHistoryStartDate: Date {
        let calendar = Calendar.current
        let earliest = calendar.date(byAdding: .day, value: -(Self.historyDays - 1), to: Date()) ?? Date()
        return calendar.startOfDay(for: earliest)
    }

    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private var typesToRead: Set<HKObjectType> {
        [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.workoutType(),
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
        ]
    }

    /// Called on launch. HealthKit authorization persists across sessions, so if
    /// the user was already asked in a prior session we skip the prompt entirely
    /// and load data immediately; otherwise we surface the explainer.
    func start() async {
        // Spans the whole launch path, so this interval is the headline "time until the
        // app has data" measurement to compare before and after caching changes.
        let signposter = Signposts.healthKit
        let interval = signposter.beginInterval("Startup", id: signposter.makeSignpostID())
        let started = ContinuousClock().now
        Signposts.logger.notice("Startup began")
        defer {
            signposter.endInterval("Startup", interval)
            let elapsed = Signposts.milliseconds(started, ContinuousClock().now)
            Signposts.logger.notice("""
                Startup completed in \(elapsed, format: .fixed(precision: 1), privacy: .public) ms \
                (phase: \(String(describing: self.accessPhase), privacy: .public))
                """)
        }

        guard isHealthKitAvailable else {
            accessPhase = .needsAuthorization
            return
        }
        if await requestStatus() == .unnecessary {
            await activate()
        } else {
            accessPhase = .needsAuthorization
        }
    }

    /// Whether the system would present an authorization prompt for our types.
    /// Note: this never reveals whether read access was *granted* — Apple hides
    /// read authorization for privacy — only whether a request is still needed.
    private func requestStatus() async -> HKAuthorizationRequestStatus {
        await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: typesToRead) { status, _ in
                continuation.resume(returning: status)
            }
        }
    }

    func requestAuthorization() async {
        guard isHealthKitAvailable else { return }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            await activate()
        } catch {
            accessPhase = .needsAuthorization
        }
    }

    /// Shared post-authorization setup: load HR parameters, start observing, and
    /// fetch. Used both after a fresh grant and when access already persisted.
    private func activate() async {
        accessPhase = .ready
        loadMaxHeartRate()
        await loadRestingHeartRate()

        // Publish whatever the last session cached before touching HealthKit, so the UI
        // paints immediately and the refresh below just updates it in place.
        workoutCache = await WorkoutCacheStore.load()
        if !workoutCache.isEmpty {
            publishSeries()
        }

        startObservingWorkouts()
        await fetchAllZoneData()
    }

    private func loadMaxHeartRate() {
        do {
            let dob = try healthStore.dateOfBirthComponents()
            if let year = dob.year {
                let age = Calendar.current.component(.year, from: Date()) - year
                maxHeartRate = Double(220 - age)
            }
        } catch {
            maxHeartRate = 190
        }
    }

    private func loadRestingHeartRate() async {
        let signposter = Signposts.healthKit
        let interval = signposter.beginInterval("Resting heart-rate query", id: signposter.makeSignpostID())
        defer { signposter.endInterval("Resting heart-rate query", interval) }

        guard let type = HKObjectType.quantityType(forIdentifier: .restingHeartRate) else { return }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let sample: HKQuantitySample? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample])?.first)
            }
            healthStore.execute(query)
        }

        if let sample {
            restingHeartRate = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }
    }

    private func startObservingWorkouts() {
        guard workoutObserverQuery == nil else { return }

        let query = HKObserverQuery(sampleType: HKObjectType.workoutType(), predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil, let self else {
                completionHandler()
                return
            }
            Task {
                await self.fetchAllZoneData()
            }
            completionHandler()
        }
        workoutObserverQuery = query
        healthStore.execute(query)
    }

    @MainActor
    func fetchAllZoneData() async {
        guard !isLoading else { return }
        lastFetchDate = Date()
        isLoading = true
        defer { isLoading = false }

        let signposter = Signposts.healthKit
        let fetchInterval = signposter.beginInterval("Fetch zone data", id: signposter.makeSignpostID())
        let clock = ContinuousClock()
        let started = clock.now

        // Step 1: fetch workout metadata for the history window — 1 query, no HR data
        let metadataInterval = signposter.beginInterval("Workout metadata query", id: signposter.makeSignpostID())
        let currentWorkouts = await fetchWorkoutObjects(since: historyStartDate)
        signposter.endInterval("Workout metadata query", metadataInterval)
        let afterMetadata = clock.now

        // Step 2: diff UUIDs
        let currentIDs = Set(currentWorkouts.map { $0.uuid })
        let cachedIDs  = Set(workoutCache.keys)
        let deletedIDs = cachedIDs.subtracting(currentIDs)
        let addedIDs   = currentIDs.subtracting(cachedIDs)

        // Step 3: detect modified workouts (same UUID, different endDate)
        let modifiedIDs = currentIDs.subtracting(addedIDs).filter { id in
            guard let cached  = workoutCache[id],
                  let current = currentWorkouts.first(where: { $0.uuid == id })
            else { return false }
            return cached.endDate != current.endDate
        }

        // Step 4: evict deleted and modified entries. Cached histograms don't depend on
        // the heart-rate parameters, so a max/resting HR change no longer invalidates
        // anything — it's resolved fresh in step 6.
        for id in deletedIDs.union(modifiedIDs) {
            workoutCache.removeValue(forKey: id)
        }

        // Step 5: fetch heart-rate histograms for new and modified workouts
        let idsToFetch      = addedIDs.union(modifiedIDs)
        let workoutsToFetch = currentWorkouts.filter { idsToFetch.contains($0.uuid) }
        // These are the round trips a persistent cache would eliminate: one per workout,
        // serialized, and on a cold launch that means every workout in the window.
        let heartRateInterval = signposter.beginInterval("Heart-rate queries", id: signposter.makeSignpostID())
        var sampleCount = 0
        await withTaskGroup(of: (CachedWorkout, Int).self) { group in
            var pending = workoutsToFetch.makeIterator()
            var running = 0
            while running < maxConcurrentQueries, let workout = pending.next() {
                group.addTask { await self.fetchHistogram(for: workout) }
                running += 1
            }
            while let (cached, samples) = await group.next() {
                workoutCache[cached.uuid] = cached
                sampleCount += samples
                if let workout = pending.next() {
                    group.addTask { await self.fetchHistogram(for: workout) }
                }
            }
        }
        signposter.endInterval("Heart-rate queries", heartRateInterval)
        let afterHeartRate = clock.now

        // Step 6: resolve zones from the cached histograms and recompute the series —
        // no HealthKit queries
        let recomputeInterval = signposter.beginInterval("Recompute series", id: signposter.makeSignpostID())
        publishSeries()
        signposter.endInterval("Recompute series", recomputeInterval)

        // Step 7: persist the cache when it actually changed, so routine refreshes don't
        // rewrite the whole file
        if !addedIDs.isEmpty || !modifiedIDs.isEmpty || !deletedIDs.isEmpty {
            let cutoff = historyStartDate
            let retained = workoutCache.values.filter { $0.startDate >= cutoff }
            workoutCache = Dictionary(uniqueKeysWithValues: retained.map { ($0.uuid, $0) })
            await WorkoutCacheStore.save(retained)
        }

        let finished = clock.now
        signposter.endInterval("Fetch zone data", fetchInterval)
        Signposts.logger.notice("""
            Fetched zone data in \(Signposts.milliseconds(started, finished), format: .fixed(precision: 1), privacy: .public) ms — \
            \(currentWorkouts.count, privacy: .public) workouts in window, \
            \(workoutsToFetch.count, privacy: .public) needed heart-rate queries \
            (\(sampleCount, privacy: .public) samples) | \
            metadata \(Signposts.milliseconds(started, afterMetadata), format: .fixed(precision: 1), privacy: .public) ms, \
            heart rate \(Signposts.milliseconds(afterMetadata, afterHeartRate), format: .fixed(precision: 1), privacy: .public) ms, \
            recompute \(Signposts.milliseconds(afterHeartRate, finished), format: .fixed(precision: 1), privacy: .public) ms
            """)
    }

    /// Resolves every cached workout's histogram against the current heart-rate
    /// parameters and republishes the derived series. Pure CPU — no HealthKit access —
    /// so it's cheap enough to run whenever the cache or those parameters change.
    private func publishSeries() {
        let resolved = workoutCache.values.map { cached in
            var aggregate = ZoneMinutes()
            var hourly: [Date: ZoneMinutes] = [:]
            for hour in cached.histogram {
                let minutes = hour.zoneMinutes(maxHeartRate: maxHeartRate, restingHeartRate: restingHeartRate)
                aggregate += minutes
                hourly[hour.hourStart, default: ZoneMinutes()] += minutes
            }
            return ResolvedWorkout(startDate: cached.startDate, zoneMinutes: aggregate, hourlyZoneMinutes: hourly)
        }

        weeklyHistory = recomputeWeeklyHistory(from: resolved)
        dailyHistory = recomputeDailyHistory(from: resolved)
        let averages = recomputeAverages(from: resolved)
        weekdayAverages = averages.weekday
        hourlyAveragesByWeekday = averages.hourly
    }

    private func fetchWorkoutObjects(since startDate: Date) async -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
            options: .strictStartDate
        )
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    /// Buckets cached workouts into contiguous calendar weeks across the history window,
    /// including empty weeks so the timeline has no gaps.
    private func recomputeWeeklyHistory(from resolved: [ResolvedWorkout]) -> [WeeklyZoneData] {
        let calendar = Calendar.zoneScope
        let now = Date()
        let start = historyStartDate

        // Number of week buckets from the history start through the current week.
        let weekSpan = calendar.dateComponents([.weekOfYear], from: start, to: now).weekOfYear ?? 0
        let weekStarts: [Date] = (0...max(0, weekSpan)).compactMap {
            calendar.date(byAdding: .weekOfYear, value: $0, to: start)
        }

        var buckets: [Date: ZoneMinutes] = Dictionary(uniqueKeysWithValues: weekStarts.map { ($0, ZoneMinutes()) })
        var dayBuckets: [Date: ZoneMinutes] = [:]
        for entry in resolved {
            if let weekStart = calendar.dateInterval(of: .weekOfYear, for: entry.startDate)?.start,
               buckets[weekStart] != nil {
                buckets[weekStart]? += entry.zoneMinutes
            }
            dayBuckets[calendar.startOfDay(for: entry.startDate), default: ZoneMinutes()] += entry.zoneMinutes
        }

        return weekStarts.map { weekStart in
            let days = (0..<7).compactMap { offset -> DailyZoneData? in
                guard let dayStart = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
                return DailyZoneData(dayStart: dayStart, zoneMinutes: dayBuckets[dayStart] ?? ZoneMinutes())
            }
            return WeeklyZoneData(weekStart: weekStart, zoneMinutes: buckets[weekStart] ?? ZoneMinutes(), days: days)
        }
    }

    /// Buckets cached workouts into contiguous calendar days across the daily window,
    /// including empty days so the timeline has no gaps.
    private func recomputeDailyHistory(from resolved: [ResolvedWorkout]) -> [DailyZoneData] {
        let calendar = Calendar.current
        let start = dailyHistoryStartDate

        let dayStarts: [Date] = (0..<Self.historyDays).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }

        var buckets: [Date: ZoneMinutes] = Dictionary(uniqueKeysWithValues: dayStarts.map { ($0, ZoneMinutes()) })
        var hourBuckets: [Date: ZoneMinutes] = [:]
        for entry in resolved {
            let dayStart = calendar.startOfDay(for: entry.startDate)
            if buckets[dayStart] != nil {
                buckets[dayStart]? += entry.zoneMinutes
            }
            for (hourStart, minutes) in entry.hourlyZoneMinutes {
                hourBuckets[hourStart, default: ZoneMinutes()] += minutes
            }
        }

        return dayStarts.map { dayStart in
            let hours = (0..<24).compactMap { hour -> HourlyZoneData? in
                guard let hourStart = calendar.date(byAdding: .hour, value: hour, to: dayStart) else { return nil }
                return HourlyZoneData(hourStart: hourStart, zoneMinutes: hourBuckets[hourStart] ?? ZoneMinutes())
            }
            return DailyZoneData(dayStart: dayStart, zoneMinutes: buckets[dayStart] ?? ZoneMinutes(), hours: hours)
        }
    }

    /// Averages zone minutes per weekday, and per hour within each weekday, over the
    /// `averageWeeks` most recent *complete* weeks — the current partial week is excluded
    /// so it can't dilute the averages. Rest days count as zero (the divisor is always
    /// the full week count), giving a true "average Monday" that active days exceed.
    private func recomputeAverages(from resolved: [ResolvedWorkout]) -> (weekday: [ZoneMinutes], hourly: [[ZoneMinutes]]) {
        let calendar = Calendar.zoneScope
        let now = Date()
        let windowEnd = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let windowStart = calendar.date(byAdding: .weekOfYear, value: -Self.averageWeeks, to: windowEnd) ?? windowEnd

        var weekdaySums = [ZoneMinutes](repeating: ZoneMinutes(), count: 7)
        var hourlySums = [[ZoneMinutes]](repeating: [ZoneMinutes](repeating: ZoneMinutes(), count: 24), count: 7)

        for entry in resolved where entry.startDate >= windowStart && entry.startDate < windowEnd {
            weekdaySums[calendar.mondayFirstIndex(for: entry.startDate)] += entry.zoneMinutes
            for (hourStart, minutes) in entry.hourlyZoneMinutes {
                let weekday = calendar.mondayFirstIndex(for: hourStart)
                let hour = calendar.component(.hour, from: hourStart)
                hourlySums[weekday][hour] += minutes
            }
        }

        let factor = 1 / Double(Self.averageWeeks)
        return (
            weekdaySums.map { $0.scaled(by: factor) },
            hourlySums.map { $0.map { $0.scaled(by: factor) } }
        )
    }

    /// Reads a workout's heart-rate samples and reduces them to per-hour BPM histograms,
    /// returning the sample count for the signpost summary.
    private func fetchHistogram(for workout: HKWorkout) async -> (CachedWorkout, Int) {
        let signposter = Signposts.healthKit
        let interval = signposter.beginInterval("Heart-rate query", id: signposter.makeSignpostID())
        defer { signposter.endInterval("Heart-rate query", interval) }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.quantityType(forIdentifier: .heartRate)!,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }

        let cached = CachedWorkout(
            uuid: workout.uuid,
            startDate: workout.startDate,
            endDate: workout.endDate,
            histogram: buildHistogram(from: samples, workoutEnd: workout.endDate)
        )
        return (cached, samples.count)
    }

    /// Reduces a workout's heart-rate samples to minutes spent at each whole BPM within
    /// each clock hour.
    ///
    /// Each sample owns the interval until the next one starts (or the workout's end),
    /// clamped to 5 minutes so a single stale sample can't inflate a gap. The result
    /// deliberately carries no zone information — zones are derived later from the
    /// current max/resting heart rate, which is what keeps the cache valid when those
    /// change.
    private func buildHistogram(from samples: [HKQuantitySample], workoutEnd: Date) -> [HourlyHeartRateHistogram] {
        var byHour: [Date: [Int: Double]] = [:]
        let calendar = Calendar.zoneScope
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

        for (index, sample) in samples.enumerated() {
            let nextStart = index + 1 < samples.count ? samples[index + 1].startDate : workoutEnd
            let rawDuration = nextStart.timeIntervalSince(sample.startDate)
            let minutes = min(rawDuration, 5 * 60) / 60

            let bpm = Int(sample.quantity.doubleValue(for: beatsPerMinute).rounded())
            guard let hourStart = calendar.dateInterval(of: .hour, for: sample.startDate)?.start else { continue }
            byHour[hourStart, default: [:]][bpm, default: 0] += minutes
        }

        return byHour
            .map { HourlyHeartRateHistogram(hourStart: $0.key, minutesByBPM: $0.value) }
            .sorted { $0.hourStart < $1.hourStart }
    }
}
