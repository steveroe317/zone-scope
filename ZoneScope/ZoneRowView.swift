//
//  ZoneRowView.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import SwiftUI

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
