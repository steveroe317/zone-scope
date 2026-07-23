# ZoneScope Architecture

## Overview

ZoneScope is a single-screen iOS app that reads a user's workouts and heart-rate
samples from HealthKit and visualizes how much time they spent in each of five
heart-rate training zones over a selectable time period (Day, Week, Month,
Year). The chart can optionally screen out Zone 1 (Recovery) to focus on the
higher-intensity zones. It is a read-only client of Apple Health: it writes
nothing back, has no network layer, no accounts, and stores no domain data of
its own — it persists only a single UI preference (the Zone 1 filter) via
`@AppStorage`.

- **Platform:** iOS 26.2+ (deployment target)
- **Language / UI:** Swift, SwiftUI, with `@Observable` for shared state
- **Data source:** HealthKit (`HKHealthStore`)
- **Concurrency:** Swift structured concurrency (`async/await`), with
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` so types are main-actor-isolated by
  default
- **Dependencies:** None (no third-party frameworks, no Swift Package
  dependencies)
- **Bundle identifier:** `com.roedesigns.test.ZoneScope`

## File structure

```
ZoneScope/
├── ZoneScope/                     # App source
│   ├── ZoneScopeApp.swift         # @main entry point / WindowGroup
│   ├── ContentView.swift          # Root view: period picker, state routing, options menu
│   ├── AuthPromptView.swift       # Empty-state view prompting HealthKit access
│   ├── ZoneChartView.swift        # Assembles four or five zone rows + total
│   ├── ZoneRowView.swift          # One zone's bar + labels
│   ├── HealthKitManager.swift     # Observable model: HealthKit access + zone math
│   ├── TimeFormatting.swift       # formatTime() free function
│   ├── ZoneScope.entitlements     # HealthKit entitlement
│   └── Assets.xcassets/           # App icon, accent color
├── ZoneScope.xcodeproj/           # Xcode project (single app target)
├── design/                        # App-icon concepts (SVG / Pixelmator source)
├── docs/
│   ├── architecture.md            # This document
│   └── code-reviews/              # Dated code-review reports
├── AGENTS.md / CLAUDE.md          # Swift/SwiftUI style guidelines for AI agents
```

There is a single application target and **no test target**.

## Layered design

The app has a clean, if small, separation between the data/domain layer and the
presentation layer. All state flows one direction: `HealthKitManager` owns the
truth, views observe it and render.

### Data & domain layer (`HealthKitManager.swift`)

This file holds three domain types plus the model class:

- **`TimePeriod`** — an `enum` (`.day`, `.week`, `.month`, `.year`) that is both
  the segmented-picker model and the definition of each query window via its
  `startDate` computed property.
- **`ZoneMinutes`** — a value type accumulating minutes across the five zones,
  with a `total` and an integer `subscript(zone:)` for indexed access.
- **`CachedWorkout`** (file-private) — a per-workout cache entry recording the
  computed `ZoneMinutes` plus the max/resting HR values it was computed with, so
  the cache can be invalidated when those inputs change.
- **`HealthKitManager`** — a `@MainActor @Observable final class` that is the
  single source of truth for authorization state, loading state, the computed
  `zoneData`, and the HR parameters (`maxHeartRate`, `restingHeartRate`).

### Presentation layer (SwiftUI views)

Views are small, single-responsibility structs in separate files (per the
project's style guidelines):

- **`ContentView`** — owns the `HealthKitManager` via `@State` and routes between
  mutually exclusive UI states (see State machine below). Also owns the
  `@AppStorage("hideZone1")` preference and exposes it through a toolbar `Menu`
  toggle (shown only when authorized).
- **`AuthPromptView`** — pure presentational empty state; takes an `action`
  closure invoked when the user taps "Grant Access."
- **`ZoneChartView`** — receives a `ZoneMinutes` value, HR parameters, and a
  `hideZone1` flag. Computes `visibleZones`, renormalizes bar widths to the max
  of the *visible* zones, and shows a total summed over only the visible zones.
  Derives per-zone BPM boundary labels from the HR parameters via a
  `zoneLimit(for:)` lookup.
- **`ZoneRowView`** — renders one zone: name/number, a proportional bar, and the
  minutes/BPM-range labels.

The views are strictly driven by data passed in; none of them touch HealthKit
directly. `HealthKitManager` is injected only into `ContentView`; the chart views
receive plain value types, which keeps them trivially previewable and testable.

## Runtime dynamics

### State machine (`ContentView`)

`ContentView` renders exactly one of these branches, checked in order:

1. **HealthKit unavailable** → `ContentUnavailableView` ("HealthKit Unavailable")
2. **Not authorized** → `AuthPromptView` (tapping triggers
   `requestAuthorization()`)
3. **Loading** → `ProgressView`
4. **Have data for the selected period** (`zoneMinutes.total > 0`) →
   `ZoneChartView`
5. **Otherwise** → `ContentUnavailableView` ("No Workout Data")

The data-present check (step 4) keys on the *full* `zoneMinutes.total`, not the
filtered total, so a user whose only data is Zone 1 still lands on the chart
(with empty 2–5 bars and a 0:00 visible total) rather than the "No Workout Data"
state. The options toolbar menu holding the Zone 1 toggle appears whenever
`authorized`, regardless of which of branches 3–5 is showing.

### Authorization and data-load flow

```
User taps "Grant Access"
        │
        ▼
requestAuthorization()
        │  requests read access: heartRate, restingHeartRate,
        │  workoutType, dateOfBirth
        ├─► loadMaxHeartRate()        (220 − age, from date of birth)
        ├─► loadRestingHeartRate()    (most recent restingHeartRate sample)
        ├─► startObservingWorkouts()  (HKObserverQuery on workoutType)
        └─► fetchAllZoneData()
```

`maxHeartRate` defaults to 190 and `restingHeartRate` to 60 when the underlying
data is unavailable.

### The zone-data pipeline (`fetchAllZoneData`)

This is the core of the app and is designed around an incremental,
UUID-keyed cache (`workoutCache: [UUID: CachedWorkout]`) so that re-fetches only
recompute what actually changed:

1. **Fetch workout metadata** for the widest window (one year) — a single
   `HKSampleQuery` for `workoutType`, no heart-rate data yet.
2. **Diff UUIDs** against the cache to find added and deleted workouts.
3. **Detect modified** workouts (same UUID, different `endDate`).
4. **Detect invalidated** entries whose cached max/resting HR differs from the
   current values by more than `hrParamTolerance` (0.5 BPM).
5. **Evict** deleted, modified, and invalidated entries from the cache.
6. **Fetch heart-rate samples and recompute zones** only for the added, modified,
   and invalidated workouts (`fetchHRZoneMinutes` → `calculateZoneMinutes`).
7. **Recompute period totals** (`recomputeZoneData`) for all four `TimePeriod`s
   purely from the in-memory cache — no additional HealthKit queries.

`isLoading` guards against overlapping runs (early-return if already loading),
and `lastFetchDate` records the run time to drive throttled refreshes.

### Zone calculation (`calculateZoneMinutes`)

Given time-ordered heart-rate samples for one workout:

- Each sample "owns" the interval until the next sample's start (or the workout
  end for the last sample). That raw duration is **clamped to 5 minutes** to
  avoid a single stale sample inflating a zone across a gap.
- Intensity is computed with the **Heart Rate Reserve (Karvonen)** method:
  `pct = (hr − restingHR) / (maxHR − restingHR)`.
- The percentage is bucketed into five zones at boundaries **60% / 70% / 80% /
  90%** (Zone 1 `<60%` … Zone 5 `≥90%`).

`ZoneChartView` mirrors these same boundaries via its `zoneLimit(for:)` lookup to
render the human-readable BPM range labels shown next to each zone, and renders
only the currently visible zones (see Zone display filter below).

### Zone display filter

An optional "Hide Zone 1 (Recovery)" toggle lets the user drop Zone 1 from the
chart. It is:

- **Persisted** as `@AppStorage("hideZone1")` on `ContentView`, surviving app
  relaunches, and reached through a toolbar `Menu`.
- **Presentation-layer only.** The flag never reaches `HealthKitManager`, the
  workout cache, or any HealthKit query — the domain layer always computes all
  five zones. Toggling it simply passes a new `hideZone1` value into
  `ZoneChartView`, which re-renders from the already-computed `ZoneMinutes`, so
  it is instantaneous and triggers no data access.

When Zone 1 is hidden, `ZoneChartView` filters it out of `visibleZones`,
renormalizes bar widths to the largest *visible* zone (so zones 2–5 remain
readable even though Zone 1 is usually the biggest bucket), and sums the "Total"
row over the visible zones only.

### Refresh triggers

Data is refreshed on three occasions:

- **On appear** — `ContentView.task` calls `fetchAllZoneData()` if already
  authorized.
- **On workout changes** — an `HKObserverQuery` fires `fetchAllZoneData()`
  whenever HealthKit reports new/changed workouts.
- **On foreground** — `onChange(of: scenePhase)` refetches when the app becomes
  active, but only if authorized and the last fetch was more than 15 minutes ago
  (throttling).

Because period totals are recomputed from the cache, switching the segmented
`TimePeriod` picker is instantaneous and triggers no HealthKit access.

## Concurrency model

- The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so types are
  main-actor-isolated by default; `HealthKitManager` is additionally annotated
  `@MainActor @Observable`.
- HealthKit's callback-based `HKSampleQuery` APIs are bridged to `async/await`
  with `withCheckedContinuation`, so the manager exposes only structured-
  concurrency methods. There is no GCD (`DispatchQueue`) usage.
- Because state is main-actor-isolated, SwiftUI observation and mutation are
  free of data races by construction. The observer query's completion handler
  hops back onto the main actor via a `Task`.

## Design notes, constraints, and trade-offs

- **Minimal persistence.** Domain data (the workout cache) is in-memory only and
  rebuilt on each cold launch — the first fetch after launch pays the full
  HR-query cost for every workout in the past year. The only persisted state is
  the `hideZone1` UI preference, stored via `@AppStorage`.
- **Display-only filter.** The Zone 1 filter changes only what is shown, never
  what is fetched or computed; the domain layer is unaware of it.
- **Fixed one-year query horizon.** All periods are derived from a single
  year-window fetch, which bounds cost but also caps the "Year" view at the last
  365 days and excludes anything older.
- **HR-zone model is derived, not read.** ZoneScope computes zones itself from
  raw heart-rate samples rather than reading any zone data Apple/Watch may
  provide, which gives full control over the boundary definitions but ties
  accuracy to the max/resting HR estimates.
- **No error surfacing.** Failures in authorization or queries are swallowed
  (e.g., `authorized = false`, empty results); there is no user-facing error
  state beyond the "unavailable"/"no data" empty states.
- **Read-only entitlement.** The entitlements request HealthKit read access only
  (`toShare: []`), matching the `NSHealthShareUsageDescription` string.

## Known gaps (from code review)

See `docs/code-reviews/2026-04-09.md` for the full report. Open items at that
time included several force-unwraps on `HKObjectType` lookups, `TimePeriod` and
`ZoneMinutes` living in `HealthKitManager.swift` rather than their own files,
hardcoded frame widths in `ZoneRowView`, and — most significant architecturally —
**no unit tests** despite several pure, testable units
(`calculateZoneMinutes`, the `ZoneMinutes` subscript, `TimePeriod.startDate`, and
the cache diff/invalidation logic).

The Zone 1 filter refactor incidentally cleared two of those review items — the
`Array(zones.enumerated())` violation and `zones` not being `static let` — by
rewriting `ZoneChartView`'s row loop. The force-unwraps, type placement,
hardcoded frame widths, and no-tests gaps remain open. The filter's new
`visibleZones`, `visibleTotal`, and `zoneLimit(for:)` logic is pure and would be
straightforward to cover once a test target exists.
