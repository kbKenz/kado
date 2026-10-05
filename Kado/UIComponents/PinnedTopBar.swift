import SwiftUI
import KadoCore

/// Pins a bar (a mode switch, a day strip) under the navigation title.
///
/// On iOS 26 the navigation bar has no background of its own, only a
/// soft edge over the content. A bar added with `safeAreaInset` sat
/// below that edge, so rows scrolling up passed behind the bar and
/// showed again in the gap between it and the title. `safeAreaBar`
/// makes the bar part of the navigation bar, and its background runs
/// up under the title, so the title and the bar are one solid header
/// that the rows scroll under.
///
/// Before iOS 26 the navigation bar draws its own material, so the
/// bar stays an inset on the page's background, as before.
struct PinnedTopBar<Bar: View>: ViewModifier {
    @ViewBuilder var bar: Bar

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .safeAreaBar(edge: .top, spacing: 0) {
                    // Solid up to the top of the screen: the hard edge
                    // alone is translucent and still ghosts the rows.
                    bar.background(Color.kadoBackground.ignoresSafeArea(edges: .top))
                }
                .scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    bar.background(Color.kadoBackground, ignoresSafeAreaEdges: [])
                }
        }
    }
}

extension View {
    /// See `PinnedTopBar`.
    func pinnedTopBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(PinnedTopBar(bar: bar))
    }
}
