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
                        restingHeartRate: healthKit.restingHeartRate
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
            .task {
                if healthKit.authorized {
                    await healthKit.fetchAllZoneData()
                }
            }
        }
    }
}

struct AuthPromptView: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.fill")
                .font(.system(size: 60))
                .foregroundStyle(.red)
            Text("Heart Rate Access Required")
                .font(.title2.bold())
            Text("ZoneScope needs access to your workout and heart rate data to show your training zones.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Grant Access", action: action)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ZoneChartView: View {
    let zoneMinutes: ZoneMinutes
    let maxHeartRate: Double
    let restingHeartRate: Double

    private let zones: [(Int, String, Color)] = [
        (1, "Recovery", .gray),
        (2, "Aerobic Base", .blue),
        (3, "Tempo", .green),
        (4, "Threshold", .orange),
        (5, "Max Effort", .red)
    ]

    private var maxZoneMinutes: Double {
        [zoneMinutes.zone1, zoneMinutes.zone2, zoneMinutes.zone3, zoneMinutes.zone4, zoneMinutes.zone5].max() ?? 1
    }

    private var zoneLimits: [String] {
        let hrr = maxHeartRate - restingHeartRate
        let b = [0.60, 0.70, 0.80, 0.90].map { Int((restingHeartRate + $0 * hrr).rounded()) }
        return [
            "<\(b[0])BPM",
            "\(b[0])-\(b[1])BPM",
            "\(b[1])-\(b[2])BPM",
            "\(b[2])-\(b[3])BPM",
            "\(b[3])+BPM"
        ]
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(zones.enumerated()), id: \.element.0) { index, zoneInfo in
                let (zone, name, color) = zoneInfo
                ZoneRowView(
                    zoneNumber: zone,
                    zoneName: name,
                    color: color,
                    minutes: zoneMinutes[zone],
                    maxMinutes: maxZoneMinutes,
                    zoneLimit: zoneLimits[index]
                )
            }
            Divider()
            HStack {
                Text("Total")
                    .font(.subheadline.bold())
                Spacer()
                Text(formatTime(zoneMinutes.total))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }

}

struct ZoneRowView: View {
    let zoneNumber: Int
    let zoneName: String
    let color: Color
    let minutes: Double
    let maxMinutes: Double
    let zoneLimit: String

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Zone \(zoneNumber)")
                    .font(.caption.bold())
                Text(zoneName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.15))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(
                            width: maxMinutes > 0 ? geo.size.width * (minutes / maxMinutes) : 0,
                            height: geo.size.height
                        )
                }
            }
            .frame(height: 28)

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatTime(minutes))
                    .font(.caption.bold())
                Text(zoneLimit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 75, alignment: .trailing)
        }
        .padding(.horizontal)
    }

}

private func formatTime(_ minutes: Double) -> String {
    let totalSeconds = Int((minutes * 60).rounded())
    let s = totalSeconds % 60
    let totalMinutes = totalSeconds / 60
    if totalMinutes < 60 {
        return String(format: "%d:%02d", totalMinutes, s)
    } else {
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }
}

#Preview {
    ContentView()
}
