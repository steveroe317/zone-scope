//
//  NoWorkoutDataView.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import SwiftUI

/// Empty state shown when no workouts with heart-rate data exist for the current selection.
struct NoWorkoutDataView: View {
    var body: some View {
        ContentUnavailableView(
            "No Workout Data",
            systemImage: "figure.run",
            description: Text("No workouts with heart rate data found for this period.")
        )
    }
}
