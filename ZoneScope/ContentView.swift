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
    @AppStorage("zoneVisibility") private var zoneVisibility = ZoneVisibility.all
    @Environment(\.scenePhase) private var scenePhase

    private var visibleZones: [Zone] {
        Zone.all.filter { zoneVisibility.isVisible($0.number) }
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
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .needsAuthorization:
                        AuthPromptView {
                            Task { await healthKit.requestAuthorization() }
                        }
                    case .ready:
                        if healthKit.isLoading || healthKit.lastFetchDate == nil {
                            ProgressView("Loading zone data…")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            switch selectedMode {
                            case .history:
                                if healthKit.weeklyHistory.contains(where: { $0.zoneMinutes.total > 0 }) {
                                    WeeklyHistoryView(weeks: healthKit.weeklyHistory, visibleZones: visibleZones)
                                } else {
                                    NoWorkoutDataView()
                                }
                            case .day, .week:
                                if let period = selectedMode.aggregatePeriod,
                                   let zoneMinutes = healthKit.zoneData[period], zoneMinutes.total > 0 {
                                    ZoneChartView(
                                        zoneMinutes: zoneMinutes,
                                        maxHeartRate: healthKit.maxHeartRate,
                                        restingHeartRate: healthKit.restingHeartRate,
                                        visibleZones: visibleZones
                                    )
                                } else {
                                    NoWorkoutDataView()
                                }
                            }
                        }
                    }
                }

                Spacer()
            }
            .navigationTitle("ZoneScope")
            .toolbar {
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
