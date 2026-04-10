//
//  TimeFormatting.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation

func formatTime(_ minutes: Double) -> String {
    let totalSeconds = Int((minutes * 60).rounded())
    let duration = Duration.seconds(totalSeconds)
    if totalSeconds < 3600 {
        return duration.formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1)))
    } else {
        return duration.formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 1)))
    }
}
