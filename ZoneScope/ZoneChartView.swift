//
//  ZoneChartView.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import SwiftUI

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
