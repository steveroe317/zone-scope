//
//  Calendar+ZoneScope.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation

extension Calendar {
    /// The app's calendar: the user's current calendar but with weeks starting on
    /// **Monday**, matching Apple's Fitness app. All week bucketing, card titles,
    /// and the weekly chart use this so a "week" is consistently Monday–Sunday.
    static var zoneScope: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        return calendar
    }
}
