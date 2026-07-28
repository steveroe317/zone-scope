# ZoneScope Architecture

## Overview

ZoneScope is a single-screen iOS app that reads a user's workouts and heart-rate
samples from HealthKit and visualizes how much time they spent in each of five
heart-rate training zones. A segmented picker offers three modes: two aggregate
windows (**Day**, **Week**) rendered as a per-zone bar chart, and a **History**
mode showing a stacked bar per week across the past year. Each zone can be shown
or hidden individually (at least one always visible) to focus on the zones of
interest. It is a read-only client of Apple Health: it writes nothing back, has
no network layer, no accounts, and stores no domain data of its own — it persists
only a single UI preference (which zones are visible) via `@AppStorage`.

- **Platform:** iOS 26.2+ (deployment target)
- **Language / UI:** Swift, SwiftUI, with `@Observable` for shared state
- **Data source:** HealthKit (`HKHealthStore`)
- **Concurrency:** Swift structured concurrency (`async/await`), with
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` so types are main-actor-isolated by
  default
- **Dependencies:** None third-party. Uses the first-party **Swift Charts**
  (`import Charts`) framework for the weekly history chart; no Swift Package
  dependencies.
- **Bundle identifier:** `com.roedesigns.test.ZoneScope`

## File structure

```
ZoneScope/
├── ZoneScope/                     # App source
│   ├── ZoneScopeApp.swift         # @main entry point / WindowGroup
│   ├── ContentView.swift          # Root view: mode picker, state routing, options menu
│   ├── AuthPromptView.swift       # Empty-state view prompting HealthKit access
│   ├── ZoneChartView.swift        # Day/Week aggregate: four or five zone rows + total
│   ├── ZoneRowView.swift          # One zone's bar + labels
│   ├── WeeklyHistoryView.swift    # History mode: Swift Charts stacked bar per week
│   ├── NoWorkoutDataView.swift    # Shared "No Workout Data" empty state
│   ├── HealthKitManager.swift     # Observable model: HealthKit access + zone math
│   ├── DisplayMode.swift          # Picker selection: day / week / history
│   ├── TimePeriod.swift           # Aggregate window (day / week) + startDate
│   ├── ZoneMinutes.swift          # Per-zone minutes value type (+ summation)
│   ├── Zone.swift                 # Shared zone metadata (number / name / color)
│   ├── ZoneVisibility.swift       # Persisted set of visible zones (bitmask)
│   ├── WeeklyZoneData.swift       # One week's ZoneMinutes keyed by week start
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

### Data & domain layer

The domain types each live in their own file; `HealthKitManager.swift` holds the
model class and its file-private cache entry:

- **`TimePeriod`** (`TimePeriod.swift`) — an `enum` (`.day`, `.week`) defining
  each aggregate query window via its `startDate` computed property.
- **`ZoneMinutes`** (`ZoneMinutes.swift`) — a value type accumulating minutes
  across the five zones, with a `total`, an integer `subscript(zone:)`, and `+` /
  `+=` operators used to sum entries when aggregating.
- **`Zone`** (`Zone.swift`) — display metadata (number, name, SwiftUI `Color`)
  with a `static let all`; the single source of truth for zone identity shared by
  both `ZoneChartView` and `WeeklyHistoryView`.
- **`ZoneVisibility`** (`ZoneVisibility.swift`) — the set of visible zones,
  `RawRepresentable` as an `Int` bitmask so it persists in `@AppStorage`. Owns the
  "at least one zone visible" invariant (`setVisible`, `isLocked`, `isAllVisible`).
- **`WeeklyZoneData`** (`WeeklyZoneData.swift`) — one week's `ZoneMinutes` keyed
  by that week's start date; the element type of the history series.
- **`DisplayMode`** (`DisplayMode.swift`) — the picker's selection (`.day`,
  `.week`, `.history`); its `aggregatePeriod` maps day/week to a `TimePeriod` and
  returns `nil` for history.
- **`CachedWorkout`** (file-private in `HealthKitManager.swift`) — a per-workout
  cache entry recording the computed `ZoneMinutes` plus the max/resting HR values
  it was computed with, so the cache can be invalidated when those inputs change.
- **`HealthKitManager`** — a `@MainActor @Observable final class` that is the
  single source of truth for authorization state, loading state, the aggregate
  `zoneData`, the `weeklyHistory` series, and the HR parameters (`maxHeartRate`,
  `restingHeartRate`).

### Presentation layer (SwiftUI views)

Views are small, single-responsibility structs in separate files (per the
project's style guidelines):

- **`ContentView`** — owns the `HealthKitManager` via `@State` and routes between
  mutually exclusive UI states (see State machine below). Also owns the
  `@AppStorage("zoneVisibility")` preference, derives the visible `[Zone]` list
  passed to the chart views, and exposes the per-zone toggles (plus a "Show All
  Zones" reset) through a toolbar `Menu` (shown only when `accessPhase == .ready`).
- **`AuthPromptView`** — pure presentational empty state; takes an `action`
  closure invoked when the user taps "Grant Access."
- **`ZoneChartView`** — the Day/Week aggregate view. Receives a `ZoneMinutes`
  value, HR parameters, and the visible `[Zone]` list. Renormalizes bar widths to
  the max of the *visible* zones and shows a total summed over only those zones.
  Derives per-zone BPM boundary labels from the HR parameters via a
  `zoneLimit(for:)` lookup.
- **`ZoneRowView`** — renders one zone: name/number, a proportional bar, and the
  minutes/BPM-range labels.
- **`WeeklyHistoryView`** — the History mode. A Swift Charts stacked `BarMark`
  chart, one bar per week (height = total minutes, segments colored by the visible
  zones). Horizontally scrollable across the full ~52-week window with the most
  recent weeks anchored initially; renders only the visible `[Zone]` list it is
  given (hidden zones drop their segment and legend entry).
- **`NoWorkoutDataView`** — shared empty state used by both modes when no
  heart-rate workout data is available.

The views are strictly driven by data passed in; none of them touch HealthKit
directly. `HealthKitManager` is injected only into `ContentView`; the chart views
receive plain value types, which keeps them trivially previewable and testable.

## Runtime dynamics

### State machine (`ContentView`)

`ContentView` first shows `ContentUnavailableView` ("HealthKit Unavailable") when
HealthKit is unavailable; otherwise it renders on `HealthKitManager.accessPhase`:

1. **`.determining`** → `ProgressView` (the brief launch check; avoids flashing the
   auth explainer for a returning user).
2. **`.needsAuthorization`** → `AuthPromptView` (tapping triggers
   `requestAuthorization()`).
3. **`.ready`** → `ProgressView` while the first fetch is pending
   (`isLoading || lastFetchDate == nil`), then `switch selectedMode`:
   - **`.day` / `.week`** → if `zoneData[period].total > 0`, `ZoneChartView`;
     else `NoWorkoutDataView`.
   - **`.history`** → if any week in `weeklyHistory` has a non-zero total,
     `WeeklyHistoryView`; else `NoWorkoutDataView`.

The Day/Week data-present check keys on the *full* `zoneMinutes.total`, not the
filtered total, so a user whose only data is Zone 1 still lands on the chart
(with empty 2–5 bars and a 0:00 visible total) rather than the "No Workout Data"
state. The options toolbar menu appears whenever `accessPhase == .ready`,
regardless of which branch is showing.

### Authorization and data-load flow

HealthKit authorization **persists across sessions** at the OS level, so ZoneScope
never re-prompts a returning user. On launch `ContentView.task` calls `start()`:

```
start()  (on launch)
   │  getRequestStatusForAuthorization(toShare: [], read: …)
   ├─ .unnecessary  (asked in a prior session) ─► activate()
   └─ .shouldRequest / .unknown ─► accessPhase = .needsAuthorization
                                    (show AuthPromptView; "Grant Access" →
                                     requestAuthorization() → activate())

activate()   (shared post-authorization setup)
   ├─► accessPhase = .ready
   ├─► loadMaxHeartRate()        (220 − age, from date of birth)
   ├─► loadRestingHeartRate()    (most recent restingHeartRate sample)
   ├─► startObservingWorkouts()  (HKObserverQuery on workoutType)
   └─► fetchAllZoneData()
```

The read types are `heartRate`, `restingHeartRate`, `workoutType`, and
`dateOfBirth`. `maxHeartRate` defaults to 190 and `restingHeartRate` to 60 when
the underlying data is unavailable.

The app stores **no** authorization token of its own. Apple deliberately hides
*read* authorization (`authorizationStatus(for:)` reports "denied" even when
granted), so `getRequestStatusForAuthorization` — which only reports whether a
prompt is still needed, never the grant result — is the correct API. A returning
user who previously *denied* access is `.unnecessary` too: `activate()` runs, the
queries return nothing, and the app shows the ordinary "No Workout Data" state
(denied and genuinely-empty are indistinguishable by design).

### The zone-data pipeline (`fetchAllZoneData`)

This is the core of the app and is designed around an incremental,
UUID-keyed cache (`workoutCache: [UUID: CachedWorkout]`) so that re-fetches only
recompute what actually changed:

1. **Fetch workout metadata** for the history window (`historyStartDate`, the
   start of the week ~52 weeks ago) — a single `HKSampleQuery` for `workoutType`,
   no heart-rate data yet.
2. **Diff UUIDs** against the cache to find added and deleted workouts.
3. **Detect modified** workouts (same UUID, different `endDate`).
4. **Detect invalidated** entries whose cached max/resting HR differs from the
   current values by more than `hrParamTolerance` (0.5 BPM).
5. **Evict** deleted, modified, and invalidated entries from the cache.
6. **Fetch heart-rate samples and recompute zones** only for the added, modified,
   and invalidated workouts (`fetchHRZoneMinutes` → `calculateZoneMinutes`).
7. **Recompute derived views** purely from the in-memory cache — no additional
   HealthKit queries: `recomputeZoneData()` sums the `.day`/`.week` aggregates,
   and `recomputeWeeklyHistory()` buckets cached workouts into contiguous
   calendar weeks (including empty weeks, so the timeline has no gaps) to build
   the `weeklyHistory` series.

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

Each of the five zones can be shown or hidden independently via per-zone toggles
in the toolbar `Menu`, plus a "Show All Zones" reset. The filter is:

- **Persisted** as `@AppStorage("zoneVisibility")` on `ContentView`. The stored
  type, `ZoneVisibility`, is `RawRepresentable` as an `Int` bitmask, so the whole
  visible set round-trips through a single `@AppStorage` key.
- **Invariant-guarded.** `ZoneVisibility` guarantees at least one zone is always
  visible: `setVisible(_:_:)` refuses to hide the last one, and the menu disables
  the sole remaining zone's toggle (`isLocked`) so the invalid state can't be
  reached. "Show All Zones" restores every zone and is disabled once
  `isAllVisible`.
- **Centralized and presentation-layer only.** `ContentView` derives the visible
  `[Zone]` list once (`Zone.all.filter { zoneVisibility.isVisible($0.number) }`)
  and passes it to both chart views, which are pure renderers with no filter
  knowledge. The visibility set never reaches `HealthKitManager`, the workout
  cache, or any HealthKit query — the domain layer always computes all five
  zones, so toggling re-renders from the already-computed data instantly with no
  data access.

Given the visible list, `ZoneChartView` renormalizes bar widths to the largest
*visible* zone and sums the "Total" over the visible zones only; `WeeklyHistoryView`
draws only the visible segments (and legend entries) in every weekly bar.

### Refresh triggers

Data is refreshed on three occasions:

- **On appear** — `ContentView.task` calls `start()`, which activates and fetches
  when access already persisted.
- **On workout changes** — an `HKObserverQuery` fires `fetchAllZoneData()`
  whenever HealthKit reports new/changed workouts.
- **On foreground** — `onChange(of: scenePhase)` refetches when the app becomes
  active, but only if `accessPhase == .ready` and the last fetch was more than 15
  minutes ago (throttling).

Because both the aggregate totals and the weekly history are recomputed from the
cache, switching the segmented `DisplayMode` picker (Day / Week / History) is
instantaneous and triggers no HealthKit access.

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
  the `zoneVisibility` UI preference (a bitmask of visible zones), stored via
  `@AppStorage`.
- **Display-only filter.** The per-zone visibility filter changes only what is
  shown, never what is fetched or computed; the domain layer is unaware of it.
- **Fixed ~52-week query horizon.** Everything is derived from a single
  `historyStartDate` fetch (`historyWeeks = 52`), which bounds cost but also caps
  the History view at the last ~52 weeks and excludes anything older.
- **HR-zone model is derived, not read.** ZoneScope computes zones itself from
  raw heart-rate samples rather than reading any zone data Apple/Watch may
  provide, which gives full control over the boundary definitions but ties
  accuracy to the max/resting HR estimates.
- **No error surfacing.** Failures in authorization or queries are swallowed
  (e.g., `accessPhase = .needsAuthorization`, empty results); there is no
  user-facing error state beyond the "unavailable"/"no data" empty states.
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

Subsequent work cleared several of those items: the Zone 1 filter refactor fixed
the `Array(zones.enumerated())` violation and made the zone list a `static let`,
and the weekly-history work moved `TimePeriod` and `ZoneMinutes` into their own
files (resolving the type-placement item). The force-unwraps on `HKObjectType`
lookups, hardcoded frame widths in `ZoneRowView`, and the **no-tests** gap remain
open. The pure logic added since — `recomputeWeeklyHistory()` bucketing, the
`ZoneMinutes` `+` operator, `ZoneVisibility` (bitmask round-trip and the
"at least one visible" invariant), `visibleTotal`, and `zoneLimit(for:)` — would
be straightforward to cover once a test target exists.
