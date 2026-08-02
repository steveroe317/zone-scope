//
//  HealthKitManager.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation
import HealthKit

private struct CachedWorkout {
    let uuid: UUID
    let startDate: Date
    let endDate: Date
    let zoneMinutes: ZoneMinutes
    let cachedWithMaxHR: Double
    let cachedWithRestingHR: Double
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
    var zoneData: [TimePeriod: ZoneMinutes] = [:]
    var weeklyHistory: [WeeklyZoneData] = []
    var dailyHistory: [DailyZoneData] = []
    private(set) var lastFetchDate: Date?

    private let healthStore = HKHealthStore()
    private var workoutObserverQuery: HKObserverQuery?
    var maxHeartRate: Double = 190
    var restingHeartRate: Double = 60

    private var workoutCache: [UUID: CachedWorkout] = [:]
    private let hrParamTolerance: Double = 0.5

    /// Number of weeks of history fetched and shown in the weekly view.
    static let historyWeeks = 52

    /// Number of days shown in the daily trends view.
    static let historyDays = 90

    /// Start of the earliest week included in the fetch/history window.
    private var historyStartDate: Date {
        let calendar = Calendar.current
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

        // Step 1: fetch workout metadata for the history window — 1 query, no HR data
        let currentWorkouts = await fetchWorkoutObjects(since: historyStartDate)

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

        // Step 4: detect HR-param-invalidated entries
        let invalidatedIDs = Set(workoutCache.values
            .filter {
                abs($0.cachedWithMaxHR     - maxHeartRate)     > hrParamTolerance ||
                abs($0.cachedWithRestingHR - restingHeartRate) > hrParamTolerance
            }
            .map { $0.uuid })

        // Step 5: evict deleted, modified, and invalidated entries
        for id in deletedIDs.union(modifiedIDs).union(invalidatedIDs) {
            workoutCache.removeValue(forKey: id)
        }

        // Step 6: fetch HR + compute zones for new, modified, and invalidated workouts
        let idsToFetch      = addedIDs.union(modifiedIDs).union(invalidatedIDs)
        let workoutsToFetch = currentWorkouts.filter { idsToFetch.contains($0.uuid) }
        for workout in workoutsToFetch {
            let mins = await fetchHRZoneMinutes(for: workout)
            workoutCache[workout.uuid] = CachedWorkout(
                uuid:                workout.uuid,
                startDate:           workout.startDate,
                endDate:             workout.endDate,
                zoneMinutes:         mins,
                cachedWithMaxHR:     maxHeartRate,
                cachedWithRestingHR: restingHeartRate
            )
        }

        // Step 7: recompute period totals, weekly, and daily history from cache — no HealthKit queries
        zoneData = recomputeZoneData()
        weeklyHistory = recomputeWeeklyHistory()
        dailyHistory = recomputeDailyHistory()
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

    private func recomputeZoneData() -> [TimePeriod: ZoneMinutes] {
        var result: [TimePeriod: ZoneMinutes] = [:]
        for period in TimePeriod.allCases {
            let windowStart = period.startDate
            var total = ZoneMinutes()
            for entry in workoutCache.values where entry.startDate >= windowStart {
                total += entry.zoneMinutes
            }
            result[period] = total
        }
        return result
    }

    /// Buckets cached workouts into contiguous calendar weeks across the history window,
    /// including empty weeks so the timeline has no gaps.
    private func recomputeWeeklyHistory() -> [WeeklyZoneData] {
        let calendar = Calendar.current
        let now = Date()
        let start = historyStartDate

        // Number of week buckets from the history start through the current week.
        let weekSpan = calendar.dateComponents([.weekOfYear], from: start, to: now).weekOfYear ?? 0
        let weekStarts: [Date] = (0...max(0, weekSpan)).compactMap {
            calendar.date(byAdding: .weekOfYear, value: $0, to: start)
        }

        var buckets: [Date: ZoneMinutes] = Dictionary(uniqueKeysWithValues: weekStarts.map { ($0, ZoneMinutes()) })
        for entry in workoutCache.values {
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: entry.startDate)?.start,
                  buckets[weekStart] != nil else { continue }
            buckets[weekStart]? += entry.zoneMinutes
        }

        return weekStarts.map { WeeklyZoneData(weekStart: $0, zoneMinutes: buckets[$0] ?? ZoneMinutes()) }
    }

    /// Buckets cached workouts into contiguous calendar days across the daily window,
    /// including empty days so the timeline has no gaps.
    private func recomputeDailyHistory() -> [DailyZoneData] {
        let calendar = Calendar.current
        let start = dailyHistoryStartDate

        let dayStarts: [Date] = (0..<Self.historyDays).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }

        var buckets: [Date: ZoneMinutes] = Dictionary(uniqueKeysWithValues: dayStarts.map { ($0, ZoneMinutes()) })
        for entry in workoutCache.values {
            let dayStart = calendar.startOfDay(for: entry.startDate)
            guard buckets[dayStart] != nil else { continue }
            buckets[dayStart]? += entry.zoneMinutes
        }

        return dayStarts.map { DailyZoneData(dayStart: $0, zoneMinutes: buckets[$0] ?? ZoneMinutes()) }
    }

    private func fetchHRZoneMinutes(for workout: HKWorkout) async -> ZoneMinutes {
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

        return calculateZoneMinutes(from: samples, workoutEnd: workout.endDate)
    }

    private func calculateZoneMinutes(from samples: [HKQuantitySample], workoutEnd: Date) -> ZoneMinutes {
        var result = ZoneMinutes()
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

        for (i, sample) in samples.enumerated() {
            let nextStart = i + 1 < samples.count ? samples[i + 1].startDate : workoutEnd
            let rawDuration = nextStart.timeIntervalSince(sample.startDate)
            let clampedDuration = min(rawDuration, 5 * 60)
            let minutes = clampedDuration / 60

            let hr = sample.quantity.doubleValue(for: beatsPerMinute)
            let hrr = maxHeartRate - restingHeartRate
            let pct = (hr - restingHeartRate) / hrr

            if pct < 0.60 {
                result.zone1 += minutes
            } else if pct < 0.70 {
                result.zone2 += minutes
            } else if pct < 0.80 {
                result.zone3 += minutes
            } else if pct < 0.90 {
                result.zone4 += minutes
            } else {
                result.zone5 += minutes
            }
        }
        return result
    }
}
