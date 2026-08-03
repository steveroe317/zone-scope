//
//  ContentView.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import SwiftUI

struct ContentView: View {
    @State private var healthKit = HealthKitManager()
    @State private var selectedMode: DisplayMode = .week
    @State private var showingAbout = false
    @AppStorage("zoneVisibility") private var zoneVisibility = ZoneVisibility.all
    @AppStorage("trendGranularity") private var trendGranularity = TrendGranularity.weekly
    @Environment(\.scenePhase) private var scenePhase

    private var visibleZones: [Zone] {
        Zone.all.filter { zoneVisibility.isVisible($0.number) }
    }

    /// One y-axis bound for every week card's chart, so paging the carousel doesn't
    /// rescale it. Averages are folded in defensively — they sit below the data max in
    /// practice, but the averaging window and the retained history don't align exactly.
    private var weeklyChartUpperBound: Double {
        ZoneChartScale.upperBound(
            over: healthKit.weeklyHistory.flatMap(\.days).map(\.zoneMinutes) + healthKit.weekdayAverages,
            visibleZones: visibleZones
        )
    }

    /// The same shared bound for every day card's hourly chart.
    private var dailyChartUpperBound: Double {
        ZoneChartScale.upperBound(
            over: healthKit.dailyHistory.flatMap(\.hours).map(\.zoneMinutes)
                + healthKit.hourlyAveragesByWeekday.flatMap { $0 },
            visibleZones: visibleZones
        )
    }

    /// Whether the Trends charts are currently on screen — gates the bottom
    /// granularity control so it appears only alongside them.
    private var isShowingTrends: Bool {
        selectedMode == .history
            && healthKit.accessPhase == .ready
            && !(healthKit.isLoading || healthKit.lastFetchDate == nil)
    }

    private func visibilityBinding(for number: Int) -> Binding<Bool> {
        Binding(
            get: { zoneVisibility.isVisible(number) },
            set: { zoneVisibility.setVisible(number, $0) }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Display", selection: $selectedMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Group {
                    if !healthKit.isHealthKitAvailable {
                        ContentUnavailableView(
                            "HealthKit Unavailable",
                            systemImage: "heart.slash",
                            description: Text("HealthKit is not available on this device.")
                        )
                    } else {
                        switch healthKit.accessPhase {
                        case .determining:
                            ProgressView()
                        case .needsAuthorization:
                            AuthPromptView {
                                Task { await healthKit.requestAuthorization() }
                            }
                        case .ready:
                            if healthKit.isLoading || healthKit.lastFetchDate == nil {
                                ProgressView("Loading zone data…")
                            } else {
                                switch selectedMode {
                                case .history:
                                    TrendsView(
                                        dailyHistory: healthKit.dailyHistory,
                                        weeklyHistory: healthKit.weeklyHistory,
                                        visibleZones: visibleZones,
                                        granularity: trendGranularity
                                    )
                                case .day:
                                    ZonePeriodCarousel(
                                        points: healthKit.dailyHistory,
                                        component: .day,
                                        maxHeartRate: healthKit.maxHeartRate,
                                        restingHeartRate: healthKit.restingHeartRate,
                                        visibleZones: visibleZones
                                    ) { day in
                                        ZoneBarChart(
                                            points: day.hours,
                                            visibleZones: visibleZones,
                                            component: .hour,
                                            averages: healthKit.hourlyAveragesByWeekday[
                                                Calendar.zoneScope.mondayFirstIndex(for: day.dayStart)
                                            ],
                                            upperBound: dailyChartUpperBound
                                        )
                                    }
                                case .week:
                                    ZonePeriodCarousel(
                                        points: healthKit.weeklyHistory,
                                        component: .weekOfYear,
                                        maxHeartRate: healthKit.maxHeartRate,
                                        restingHeartRate: healthKit.restingHeartRate,
                                        visibleZones: visibleZones
                                    ) { week in
                                        ZoneBarChart(
                                            points: week.days,
                                            visibleZones: visibleZones,
                                            component: .day,
                                            averages: healthKit.weekdayAverages,
                                            upperBound: weeklyChartUpperBound
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                if isShowingTrends {
                    Picker("Trend granularity", selection: $trendGranularity) {
                        ForEach(TrendGranularity.allCases) { granularity in
                            Text(granularity.rawValue).tag(granularity)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("ZoneScope")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("About", systemImage: "info.circle") {
                        showingAbout = true
                    }
                }
                if healthKit.accessPhase == .ready {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            ForEach(Zone.all) { zone in
                                Toggle(isOn: visibilityBinding(for: zone.number)) {
                                    Text("Zone \(zone.number) · \(zone.name)")
                                }
                                .disabled(zoneVisibility.isLocked(zone.number))
                            }
                            Divider()
                            Button("Show All Zones", systemImage: "arrow.counterclockwise") {
                                zoneVisibility = .all
                            }
                            .disabled(zoneVisibility.isAllVisible)
                        } label: {
                            Label("Zones", systemImage: "slider.horizontal.3")
                        }
                        .menuActionDismissBehavior(.disabled)
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active, healthKit.accessPhase == .ready else { return }
                if let last = healthKit.lastFetchDate,
                   Date().timeIntervalSince(last) > 15 * 60 {
                    Task { await healthKit.fetchAllZoneData() }
                }
            }
            .task {
                await healthKit.start()
            }
        }
    }
}

#Preview {
    ContentView()
}
