//
//  Zone.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import SwiftUI

/// Display metadata for a heart-rate training zone, shared across the chart views.
struct Zone: Identifiable {
    let number: Int
    let name: String
    let color: Color

    var id: Int { number }

    static let all: [Zone] = [
        Zone(number: 1, name: "Recovery", color: .gray),
        Zone(number: 2, name: "Aerobic Base", color: .blue),
        Zone(number: 3, name: "Tempo", color: .green),
        Zone(number: 4, name: "Threshold", color: .orange),
        Zone(number: 5, name: "Max Effort", color: .red)
    ]
}
