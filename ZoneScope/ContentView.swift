//
//  ContentView.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import SwiftUI

struct ContentView: View {
    @State private var healthKit = HealthKitManager()
    @State private var selectedPeriod: TimePeriod = .week
    @AppStorage("hideZone1") private var hideZone1 = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(TimePeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
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
                } else if !healthKit.authorized {
                    AuthPromptView {
                        Task { await healthKit.requestAuthorization() }
                    }
                } else if healthKit.isLoading {
                    ProgressView("Loading zone data…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let zoneMinutes = healthKit.zoneData[selectedPeriod], zoneMinutes.total > 0 {
                    ZoneChartView(
                        zoneMinutes: zoneMinutes,
                        maxHeartRate: healthKit.maxHeartRate,
                        restingHeartRate: healthKit.restingHeartRate,
                        hideZone1: hideZone1
                    )
                } else {
                    ContentUnavailableView(
                        "No Workout Data",
                        systemImage: "figure.run",
                        description: Text("No workouts with heart rate data found for this period.")
                    )
                }

                Spacer()
            }
            .navigationTitle("ZoneScope")
            .toolbar {
                if healthKit.authorized {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Toggle("Hide Zone 1 (Recovery)", isOn: $hideZone1)
                        } label: {
                            Label("Options", systemImage: "slider.horizontal.3")
                        }
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active, healthKit.authorized else { return }
                if let last = healthKit.lastFetchDate,
                   Date().timeIntervalSince(last) > 15 * 60 {
                    Task { await healthKit.fetchAllZoneData() }
                }
            }
            .task {
                if healthKit.authorized {
                    await healthKit.fetchAllZoneData()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
