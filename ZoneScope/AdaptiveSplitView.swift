//
//  AdaptiveSplitView.swift
//  ZoneScope
//
//  Created by Stephen Roe on 3/12/26.
//

import SwiftUI

/// Lays out two views at roughly equal size, switching from a vertical stack when the
/// available space is taller than it is wide (portrait) to a horizontal stack when it
/// is wider than tall (landscape). Choosing by measured aspect ratio — rather than
/// size class — keeps it orientation- and device-agnostic, so it can be reused as-is
/// (e.g. on iPad or the daily card later). When `Secondary` is `EmptyView` it collapses
/// to just the primary, so callers can share one code path whether or not they pass a
/// secondary view.
struct AdaptiveSplitView<Primary: View, Secondary: View>: View {
    private let primary: Primary
    private let secondary: Secondary

    @State private var isWide = false

    init(@ViewBuilder primary: () -> Primary, @ViewBuilder secondary: () -> Secondary) {
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        if Secondary.self == EmptyView.self {
            primary
        } else {
            Group {
                if isWide {
                    HStack {
                        primary.frame(maxWidth: .infinity, maxHeight: .infinity)
                        secondary.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack {
                        primary.frame(maxWidth: .infinity, maxHeight: .infinity)
                        secondary.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { isWide = $0 }
        }
    }
}
