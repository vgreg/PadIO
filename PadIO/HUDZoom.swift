//
//  HUDZoom.swift
//  PadIO
//
//  Shared uniform scaling for the floating HUD panels.
//  Driven by the top-level `hud_zoom` config key.

import AppKit
import SwiftUI

/// Scales a HUD's content uniformly by `zoom`.
///
/// At `zoom == 1` the content is returned untouched, so the default appearance is
/// byte-for-byte unchanged.
///
/// Above that, `ScaledLayout` does the work. It has to: `.scaleEffect` is a render-only
/// transform that leaves the reported layout size alone, and every overlay controller
/// sizes its `NSPanel` from `NSHostingView.fittingSize`. Scaling without correcting the
/// reported size leaves the panel at its unscaled dimensions and clips the content.
struct HUDZoom<Content: View>: View {
    let zoom: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if zoom == 1 {
            content
        } else {
            ScaledLayout(zoom: zoom) {
                content.scaleEffect(zoom, anchor: .center)
            }
        }
    }
}

/// Reports `zoom`× its subview's ideal size, while placing the subview at its natural
/// size so a `.scaleEffect` on it fills the enlarged bounds exactly.
///
/// This is deliberately synchronous — it is correct on the very first layout pass, so
/// a panel never has to be measured, shown, and then resized.
private struct ScaledLayout: Layout {
    let zoom: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let natural = naturalSize(of: subviews)
        return CGSize(width: natural.width * zoom, height: natural.height * zoom)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let natural = naturalSize(of: subviews)
        subview.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(natural)
        )
    }

    private func naturalSize(of subviews: Subviews) -> CGSize {
        subviews.first?.sizeThatFits(.unspecified) ?? .zero
    }
}

/// Sizes a HUD panel to its SwiftUI content and positions it.
@MainActor
enum HUDPanelFitter {
    /// Lays out `hosting`, resizes `panel` to fit it, then applies `position`.
    ///
    /// The layout pass matters: `fittingSize` is stale until SwiftUI has re-laid-out for
    /// whatever content (or zoom) was just assigned.
    static func fit(panel: NSPanel, hosting: NSView, position: (NSPanel) -> Void) {
        hosting.layoutSubtreeIfNeeded()
        panel.setContentSize(hosting.fittingSize)
        position(panel)
    }
}
