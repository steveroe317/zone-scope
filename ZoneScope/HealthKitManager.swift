//
//  HealthKitManager.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation
import HealthKit

enum TimePeriod: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"

    var id: String { rawValue }

    var startDate: Date {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .day:
            return calendar.startOfDay(for: now)
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: now)!
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: now)!
        case .year:
            return calendar.date(byAdding: .year, value: -1, to: now)!
        }
    }
}

struct ZoneMinutes {
    var zone1: Double = 0
    var zone2: Double = 0
    var zone3: Double = 0
    var zone4: Double = 0
    var zone5: Double = 0

    var total: Double { zone1 + zone2 + zone3 + zone4 + zone5 }

    subscript(zone: Int) -> Double {
        switch zone {
        case 1: return zone1
        case 2: return zone2
        case 3: return zone3
        case 4: return zone4
        case 5: return zone5
        default: return 0
        }
    }
}

private struct CachedWorkout {
    let uuid: UUID
    let startDate: Date
    let endDate: Date
    let zoneMinutes: ZoneMinutes
    let cachedWithMaxHR: Double
    let cachedWithRestingHR: Double
}

@MainActor @Observable
final class HealthKitManager {
    var authorized = false
    var isLoading = false
    var zoneData: [TimePeriod: ZoneMinutes] = [:]
    private(set) var lastFetchDate: Date?

    private let healthStore = HKHealthStore()
    private var workoutObserverQuery: HKObserverQuery?
    var maxHeartRate: Double = 190
    var restingHeartRate: Double = 60

    private var workoutCache: [UUID: CachedWorkout] = [:]
    private let hrParamTolerance: Double = 0.5

    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.workoutType(),
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
        ]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            authorized = true
            loadMaxHeartRate()
            await loadRestingHeartRate()
            startObservingWorkouts()
            await fetchAllZoneData()
        } catch {
            authorized = false
        }
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

        // Step 1: fetch workout metadata for year window — 1 query, no HR data
        let currentWorkouts = await fetchWorkoutObjects(since: TimePeriod.year.startDate)

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

        // Step 7: recompute period totals from cache — no HealthKit queries
        zoneData = recomputeZoneData()
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
                total.zone1 += entry.zoneMinutes.zone1
                total.zone2 += entry.zoneMinutes.zone2
                total.zone3 += entry.zoneMinutes.zone3
                total.zone4 += entry.zoneMinutes.zone4
                total.zone5 += entry.zoneMinutes.zone5
            }
            result[period] = total
        }
        return result
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
