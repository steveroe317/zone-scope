//
//  ZoneVisibility.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import Foundation

/// The set of currently visible zones, persisted as an `Int` bitmask so it can be
/// stored directly in `@AppStorage`. Enforces the invariant that at least one zone
/// is always visible.
struct ZoneVisibility: RawRepresentable, Equatable {
    private(set) var visibleNumbers: Set<Int>

    init(visibleNumbers: Set<Int>) {
        // Enforce the invariant: never empty.
        self.visibleNumbers = visibleNumbers.isEmpty
            ? Set([Zone.all.first?.number ?? 1])
            : visibleNumbers
    }

    /// Bit `n - 1` set ⇒ zone `n` is visible.
    var rawValue: Int {
        visibleNumbers.reduce(0) { $0 | (1 << ($1 - 1)) }
    }

    init?(rawValue: Int) {
        let numbers = Zone.all.map(\.number).filter { rawValue & (1 << ($0 - 1)) != 0 }
        self.init(visibleNumbers: Set(numbers))
    }

    /// Every zone visible — the default state.
    static let all = ZoneVisibility(visibleNumbers: Set(Zone.all.map(\.number)))

    func isVisible(_ number: Int) -> Bool {
        visibleNumbers.contains(number)
    }

    var isAllVisible: Bool {
        visibleNumbers.count == Zone.all.count
    }

    /// True when `number` is the only visible zone, so its toggle must stay locked on.
    func isLocked(_ number: Int) -> Bool {
        visibleNumbers == [number]
    }

    mutating func setVisible(_ number: Int, _ show: Bool) {
        if show {
            visibleNumbers.insert(number)
        } else if visibleNumbers.count > 1 {
            // Guard the invariant: refuse to hide the last visible zone.
            visibleNumbers.remove(number)
        }
    }
}
