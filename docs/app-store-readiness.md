# ZoneScope App Store Readiness

Assessment date: 2026-08-15 · Assessed against commit `f5e1122`

## Verdict

The code is in better shape than "experimental" suggests — clean architecture, modern
Swift 6.3 concurrency, no third-party dependencies, a well-designed persistent cache.
What's missing is almost entirely the **shipping envelope**: compliance artifacts,
platform scoping, error and empty-state honesty, accessibility, and tests.

Estimate: **3–5 focused weeks** to a credible 1.0.

The gating dependency is the store-assets track (Phase 4), not the code: the privacy
policy needs somewhere to live, the icon is still in design, and screenshots can't be
captured in the Simulator because HealthKit doesn't run there. Start that track early
rather than last.

---

## Phase 1 — Compliance blockers

Without these the app either cannot be submitted or will be rejected outright.

**Decisions taken 2026-08-15:** bundle ID `com.roedesigns.zonescope` · team `D566793B9V` ·
iPhone **and** iPad · minimum iOS **26.0**.

- [x] **Add `PrivacyInfo.xcprivacy`.** Declares no tracking, no collected data types
      (nothing leaves the device), and the `UserDefaults` required-reason API
      (`NSPrivacyAccessedAPICategoryUserDefaults`, `CA92.1`) used by `@AppStorage` in
      `ContentView.swift:14-15`. The target uses a file-system-synchronized group, so
      placing the file in `ZoneScope/` is sufficient; verified present at the bundle root
      in a built `.app`.

- [x] **Draft the privacy policy.** Source text is in
      [`privacy-policy.md`](privacy-policy.md).
- [x] **Host the privacy policy and record its URL in App Store Connect.** Mandatory for
      every app, and Guideline 5.1.3 applies it specifically to HealthKit apps. Still needs
      a public URL and a contact address filled into the draft. This is the one item with a
      real-world hosting dependency — start it early.

- [x] **Replace the bundle identifier.** Now `com.roedesigns.zonescope` in both
      configurations. It also appears as the `OSLog` subsystem in `Signposts.swift:15,28`,
      which was updated to match.
- [x] **Register the App ID** for `com.roedesigns.zonescope` in the developer portal with
      the HealthKit capability enabled.

- [x] **Reconcile the development team.** All four `DEVELOPMENT_TEAM` entries (project and
      target, Debug and Release) are now `D566793B9V`.

- [x] **Scope the supported platforms.** `TARGETED_DEVICE_FAMILY = "1,2"` and
      `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"`; `SDKROOT` moved from `auto` to
      `iphoneos`, and the now-dead `MACOSX_DEPLOYMENT_TARGET`, `XROS_DEPLOYMENT_TARGET`,
      and macOS runpath settings were removed. This retires the Guideline 2.1 risk of a
      reviewer landing on the `"HealthKit Unavailable"` dead end
      (`ContentView.swift:74-78`) on a platform where HealthKit isn't available.
      **Consequence:** iPad is now a committed surface — see Phase 3 and Phase 4.

- [x] **Lower the deployment target to iOS 26.0**, recovering users on 26.0 and 26.1.
      Verified with a clean build: nothing in the codebase required 26.2.

- [x] **Remove the "not for distribution" copy** from the About sheet, the README banner,
      and the architecture doc. Done in `eb4a816`: the About sheet note was replaced by the
      health disclaimer below, the README banner is now a pre-release status line, and the
      architecture doc describes the disclaimer. A grep on 2026-11-20 found no remaining
      "not for distribution" or experimental copy.

- [x] **Set export compliance.** `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` in both
      configurations; verified as `ITSAppUsesNonExemptEncryption = false` in the built
      `Info.plist`.

- [x] **Add a health disclaimer.** The About sheet carries an "Important" section
      stating that ZoneScope is not a medical device, that zone boundaries are estimates
      (max HR is `220 − age` at `HealthKitManager.swift:167-177`, not measured), and that
      wearable heart-rate readings can be inaccurate. On 2026-11-20 it was reworded to also
      state the fallbacks: 190 bpm max HR when Health has no birth date, and 60 bpm resting
      HR when Health has no resting-HR sample. "How zones are calculated" and the README
      match.

- [ ] **Complete the app icon.** `AppIcon.appiconset` contains one 1024×1024 PNG and the
      dark and tinted appearance slots are declared but empty. iOS 26 expects an Icon
      Composer `.icon` with light/dark/tinted/clear variants. Icon design is still in
      exploration — this is on the critical path. *(The thirteen empty `mac` slots are now
      moot and can be deleted from `Contents.json`.)*

---

## Phase 2 — Review survivability

The two failure modes most likely to produce a Guideline 2.1 rejection, plus the product
surface the app is missing.

- [ ] **Fix the denied-permission dead end.** *(Largest practical rejection risk.)* Apple
      deliberately hides read-authorization denial, so `requestAuthorization` succeeds even
      when the user denies, `activate()` sets `accessPhase = .ready`
      (`HealthKitManager.swift:139-165`), every query returns `[]`, and the user sees
      *"No Workout Data."* Denied access and genuinely-empty Health are indistinguishable.
      Reviewers routinely deny permissions to test the path. Needs an empty state that
      explains both possibilities and offers a route into the Health app / Settings.

- [ ] **Make the empty state informative for a reviewer with no data.** Even with access
      granted, a review device probably has zero heart-rate workouts, and HealthKit does
      not run in the Simulator — so the entire app renders empty. Pair a genuinely
      explanatory first-run state with explicit App Review notes.

- [ ] **Surface errors.** Every HealthKit callback discards its error:
      `{ _, samples, _ in }` at `HealthKitManager.swift:193`, `:347`, and `:466`. There is
      no error state, no retry, and no surfacing. A transient failure is presented
      identically to "you did no exercise."

- [ ] **Stop dropping refreshes.** `fetchAllZoneData` returns early when `isLoading`
      (`HealthKitManager.swift:223`). If the observer query fires mid-fetch that update is
      discarded and never re-queued.

- [ ] **Add a settings screen for the numbers that drive everything.** No max-HR override,
      no zone-model choice (Karvonen vs. %max — many athletes expect the latter), no way
      to correct a bad resting HR. For a training app this is the core product surface and
      it currently doesn't exist.

---

## Phase 3 — Quality

Not individually rejection-causing, but collectively the difference between "personal
project" and "shipped app."

### Accessibility — currently zero

There is not one `accessibility*` modifier anywhere in the codebase.

- [ ] **Dynamic Type clipping.** `ZoneRowView.swift:27,52` — fixed `width: 80` and
      `width: 75` frames clip badly at large text sizes. *(Flagged in the 2026-04-09
      review; still unfixed.)*
- [ ] **Hardcoded font size.** `AuthPromptView.swift:16` — `.font(.system(size: 60))` does
      not scale. *(Also flagged in April.)*
- [ ] **Charts are invisible to VoiceOver.** `ZoneBarChart` and `ZoneHistoryChart` need
      `accessibilityChartDescriptor` or per-mark labels; the app's primary content is
      currently unreadable to VoiceOver users.
- [ ] **Color-only zone encoding.** Zone 3 green / Zone 4 orange / Zone 5 red
      (`Zone.swift:18-24`) are hard to separate for colorblind users in a stacked bar.

### Privacy hygiene

- [ ] **Health metadata in the system log.** `Signposts.logger.notice` writes workout
      counts and heart-rate sample counts with `privacy: .public`
      (`HealthKitManager.swift:302-310`, `WorkoutCacheStore.swift:56-60, 88-91`) — health-
      adjacent metadata persisted to the unified log at notice level. Gate to `.debug`, or
      make the values private in release builds.

### Testing

- [ ] **Test coverage is minimal.** The `ZoneScopeTests` target (Swift Testing, run by the
      `ZoneScope-Development` scheme through `ZoneScope.xctestplan`) was added 2026-11-20, but
      so far it only covers `ZoneVisibility`'s never-empty invariant and its bitmask round-trip.
      Also flagged in April.
      The complication: most testable logic (`buildHistogram`, `recomputeWeeklyHistory`,
      `recomputeDailyHistory`, `recomputeAverages`) is `private` inside a `@MainActor`
      class, so it needs extraction into pure `nonisolated` functions first.

      Highest-value targets:
      - `buildHistogram` bucketing, including the 5-minute sample clamp
        (`HealthKitManager.swift:489-507`)
      - Week and day bucketing (`:356-415`)
      - The averaging window's exclusion of the current partial week (`:421-444`)
      - ~~`ZoneVisibility`'s never-empty invariant~~ (done)
      - `ZoneChartScale`
      - `formatTime`

### iPad

Now a committed surface following the Phase 1 platform decision, and reviewed separately
from iPhone.

- [ ] **Give the carousel cards a real iPad layout.** `AdaptiveSplitView` switches on
      measured aspect ratio and `ZonePeriodCard`'s doc comment anticipates iPad reuse, but
      neither has been exercised on a 13" canvas. A single full-width card per page will
      read as very sparse there.
- [ ] **Check both orientations on iPad.** All four are enabled via
      `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad`, including upside-down.
- [ ] **Verify multitasking**: Split View, Slide Over, and Stage Manager resizing all
      change the container size the charts and `AdaptiveSplitView` measure.

### Correctness and consistency

- [ ] **Four force unwraps** at `HealthKitManager.swift:91`, `:92`, `:94`, `:462`, contrary
      to `AGENTS.md`. *(Flagged in April; still open.)*
- [ ] **Calendar inconsistency.** `dailyHistoryStartDate` (`:81`) and
      `recomputeDailyHistory` (`:389`) use `Calendar.current`, while the weekly paths use
      `Calendar.zoneScope`. Benign today since `firstWeekday` doesn't affect day bucketing,
      but it's a latent trap.
- [ ] **Midnight rollover.** `historyStartDate` and `dailyHistoryStartDate` are computed
      from `Date()` at call time; an app left open across midnight shows stale windows
      until the next refresh trigger.

### Localization and formatting

- [ ] **No string catalog.** No `Localizable.xcstrings`; every user-facing string is an
      inline literal. `AGENTS.md` mandates a catalog with manual symbol keys.
- [ ] **Raw interpolated numbers.** `ZoneChartView.swift:801-808` builds `"<\(b[0])BPM"` —
      unlocalized, unformatted integers, no space before the unit, contrary to the
      project's own formatting rules.

### Tooling

- [ ] **SwiftLint** is not installed and there is no `.swiftlint.yml`, despite `AGENTS.md`
      requiring a clean run before committing.
- [ ] **No CI** — no `.github/` directory or any other automation.

---

## Phase 4 — Store assets and App Store Connect

Run this track in parallel with Phases 1–3; it has the longest lead time.

- [ ] Apple Developer Program membership active on team `D566793B9V`
- [ ] App ID `com.roedesigns.zonescope` registered with the HealthKit capability
- [ ] App record created; the name "ZoneScope" confirmed available
- [ ] App icon delivered (see Phase 1)
- [ ] **Screenshots captured on real devices with real Health data** — 6.9" iPhone **and**
      13" iPad, both now required. HealthKit does not run in the Simulator, so there is no
      shortcut here.
- [ ] Description, subtitle, keywords, promotional text
- [ ] Category: Health & Fitness · age rating questionnaire completed
- [ ] Support URL (and marketing URL if desired)
- [ ] Privacy policy URL entered (see Phase 1)
- [ ] App Privacy nutrition label — "Data Not Collected" is what applies, since nothing
      leaves the device
- [ ] **App Review notes** explaining that the app requires a device with Health workout
      and heart-rate data, and that it cannot be evaluated in the Simulator
- [ ] TestFlight round before submission

---

## Schedule

| Phase | Focus | Rough effort |
|---|---|---|
| 1 | Compliance blockers | ~3 days |
| 2 | Review survivability | ~1 week |
| 3 | Quality: accessibility, tests, tooling | ~1.5 weeks |
| 4 | Store assets and App Store Connect | ~1 week, in parallel |

## What's already in good shape

Worth stating, since the list above is all deficits:

- Clean feature-oriented file layout, one type per file
- Modern Swift 6.3 concurrency throughout; `@Observable` + `@State`, no `ObservableObject`
- No third-party dependencies; first-party Swift Charts only
- Genuinely good cache design — parameter-independent histograms mean a max/resting HR
  change costs a re-bucket, not a re-read (`CachedWorkout.swift`, `HealthKitManager.swift:313-333`)
- `WorkoutCacheStore` already handles the health-data storage rules correctly: complete
  file protection, excluded from iCloud backup, schema-versioned, best-effort throughout
- `NSHealthShareUsageDescription` is present and well-written; read-only access with
  `toShare: []` is the right posture
- Correct use of `FormatStyle` over legacy `Formatter` subclasses
- Thorough documentation comments and an existing architecture doc
