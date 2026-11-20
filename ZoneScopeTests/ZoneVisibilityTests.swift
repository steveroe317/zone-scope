//
//  ZoneVisibilityTests.swift
//  ZoneScopeTests
//

import Testing
@testable import ZoneScope

/// Covers `ZoneVisibility`'s core invariant: at least one zone is always visible.
struct ZoneVisibilityTests {
    @Test func emptyInitFallsBackToOneVisibleZone() {
        let visibility = ZoneVisibility(visibleNumbers: [])
        #expect(visibility.visibleNumbers.count == 1)
    }

    @Test func zeroRawValueFallsBackToOneVisibleZone() {
        let visibility = ZoneVisibility(rawValue: 0)
        #expect(visibility?.visibleNumbers.count == 1)
    }

    @Test func refusesToHideLastVisibleZone() {
        var visibility = ZoneVisibility(visibleNumbers: [3])
        visibility.setVisible(3, false)
        #expect(visibility.isVisible(3))
        #expect(visibility.isLocked(3))
    }

    @Test func hidesZoneWhenOthersRemainVisible() {
        var visibility = ZoneVisibility.all
        visibility.setVisible(2, false)
        #expect(!visibility.isVisible(2))
        #expect(!visibility.isAllVisible)
    }

    @Test func isLockedOnlyForSoleVisibleZone() {
        let visibility = ZoneVisibility(visibleNumbers: [1, 4])
        #expect(!visibility.isLocked(1))
        #expect(!visibility.isLocked(4))
    }

    @Test(arguments: [Set([1]), Set([2, 5]), Set([1, 2, 3, 4, 5])])
    func rawValueRoundTrips(_ numbers: Set<Int>) {
        let original = ZoneVisibility(visibleNumbers: numbers)
        #expect(ZoneVisibility(rawValue: original.rawValue) == original)
    }

    @Test func allMakesEveryZoneVisible() {
        #expect(ZoneVisibility.all.isAllVisible)
    }
}
