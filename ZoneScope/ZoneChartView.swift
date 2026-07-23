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
    let hideZone1: Bool

    private static let zones: [(number: Int, name: String, color: Color)] = [
        (1, "Recovery", .gray),
        (2, "Aerobic Base", .blue),
        (3, "Tempo", .green),
        (4, "Threshold", .orange),
        (5, "Max Effort", .red)
    ]

    private var visibleZones: [(number: Int, name: String, color: Color)] {
        hideZone1 ? Self.zones.filter { $0.number != 1 } : Self.zones
    }

    private var maxZoneMinutes: Double {
        visibleZones.map { zoneMinutes[$0.number] }.max() ?? 1
    }

    private var visibleTotal: Double {
        visibleZones.reduce(0) { $0 + zoneMinutes[$1.number] }
    }

    private var zoneBoundaries: [Int] {
        let hrr = maxHeartRate - restingHeartRate
        return [0.60, 0.70, 0.80, 0.90].map { Int((restingHeartRate + $0 * hrr).rounded()) }
    }

    private func zoneLimit(for number: Int) -> String {
        let b = zoneBoundaries
        switch number {
        case 1:  return "<\(b[0])BPM"
        case 5:  return "\(b[3])+BPM"
        default: return "\(b[number - 2])-\(b[number - 1])BPM"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(visibleZones, id: \.number) { zone in
                ZoneRowView(
                    zoneNumber: zone.number,
                    zoneName: zone.name,
                    color: zone.color,
                    minutes: zoneMinutes[zone.number],
                    maxMinutes: maxZoneMinutes,
                    zoneLimit: zoneLimit(for: zone.number)
                )
            }
            Divider()
            HStack {
                Text("Total")
                    .font(.subheadline.bold())
                Spacer()
                Text(formatTime(visibleTotal))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
}

#Preview("All zones") {
    ZoneChartView(
        zoneMinutes: ZoneMinutes(zone1: 180, zone2: 90, zone3: 45, zone4: 20, zone5: 8),
        maxHeartRate: 190,
        restingHeartRate: 60,
        hideZone1: false
    )
}

#Preview("Zone 1 hidden") {
    ZoneChartView(
        zoneMinutes: ZoneMinutes(zone1: 180, zone2: 90, zone3: 45, zone4: 20, zone5: 8),
        maxHeartRate: 190,
        restingHeartRate: 60,
        hideZone1: true
    )
}
