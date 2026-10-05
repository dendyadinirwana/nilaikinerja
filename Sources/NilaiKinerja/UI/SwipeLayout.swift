import CoreGraphics
import Foundation

/// Pure layout arithmetic for `SwipeRow`, kept out of the SwiftUI view so it can
/// be tested without a running app.
///
/// The port from React Bits got this wrong once — the drawer actions were
/// stacked from the leading edge, which silently put the primary on the wrong
/// side and looked plausible in a screenshot. Geometry that a wrong answer can
/// still render is exactly the geometry that needs an assertion, so the
/// reference's positional rules live here rather than inline in the view.
enum SwipeLayout {
    /// The drag model from the reference component.
    struct Metrics {
        /// Row width.
        var width: CGFloat
        /// `actionWidth` — the width of one drawer action, and of the drawer.
        var actionWidth: CGFloat
        /// `n * actionWidth`, the drawer's total width.
        var drawerWidth: CGFloat
        /// `resistance`, clamped to `0.05...1`.
        var resistance: CGFloat
        /// `commitAt`, the fraction of the row that triggers the commit leap.
        var commitAt: CGFloat
        /// `fullSwipe && n > 0`.
        var fullSwipe: Bool
        /// `snapBounce`.
        var snapBounce: CGFloat

        init(
            width: CGFloat,
            actionWidth: CGFloat,
            actionCount: Int,
            resistance: CGFloat = 0.55,
            commitAt: CGFloat = 0.6,
            fullSwipe: Bool = true,
            snapBounce: CGFloat = 0.2
        ) {
            self.width = width
            self.actionWidth = actionWidth
            self.drawerWidth = CGFloat(actionCount) * actionWidth
            self.resistance = min(max(resistance, 0.05), 1)
            self.commitAt = commitAt
            self.fullSwipe = fullSwipe
            self.snapBounce = snapBounce
        }
    }

    /// Diminishing-returns curve for overscroll. The further past the limit, the
    /// less the row gives, which is what makes the commit point felt as
    /// resistance rather than reached by muscle memory.
    static func rubber(_ overshoot: CGFloat, _ dimension: CGFloat, _ c: CGFloat) -> CGFloat {
        (overshoot * dimension * c) / (dimension + c * abs(overshoot))
    }

    /// `max(commitAt * W, D + A / 2)` — never a commit point the row cannot
    /// physically reach.
    static func commitThreshold(_ m: Metrics) -> CGFloat {
        max(m.commitAt * m.width, m.drawerWidth + m.actionWidth / 2)
    }

    static func canCommit(_ m: Metrics) -> Bool {
        m.fullSwipe && m.drawerWidth > 0 && commitThreshold(m) <= m.width
    }

    /// Drag distance to exposed distance. The row moves freely to the drawer
    /// width, then progressively harder toward the commit point, then
    /// rubber-bands beyond it. Pulling the other way rubber-bands negative
    /// rather than clamping, which is what keeps the row feeling attached.
    static func map(_ raw: CGFloat, _ m: Metrics) -> CGFloat {
        if raw < 0 { return rubber(raw, m.width, m.resistance) }
        if raw <= m.drawerWidth { return raw }
        guard canCommit(m) else {
            return m.drawerWidth + rubber(raw - m.drawerWidth, m.width, m.resistance)
        }
        let commit = commitThreshold(m)
        let knee = m.drawerWidth + (commit - m.drawerWidth) / m.resistance
        return raw <= knee
            ? m.drawerWidth + m.resistance * (raw - m.drawerWidth)
            : commit + rubber(raw - knee, m.width, m.resistance)
    }

    /// Where a slow release at this velocity would coast to. Mirrors `project`:
    /// velocity is per-second and scaled by the decay ratio.
    static func project(_ velocity: CGFloat, decel: CGFloat = 0.998) -> CGFloat {
        ((velocity / 1000) * decel) / (1 - decel)
    }

    /// Which end the row settles at. A flick commits to the nearer end without
    /// regard for position; a slow release projects and compares to the
    /// midpoint, so a decelerating drag past halfway still opens.
    static func settleTarget(
        exposed: CGFloat,
        velocity: CGFloat,
        _ m: Metrics,
        flickVelocity: CGFloat = 110
    ) -> CGFloat {
        if abs(velocity) >= flickVelocity {
            return velocity > 0 ? m.drawerWidth : 0
        }
        return exposed + project(velocity) > m.drawerWidth / 2 ? m.drawerWidth : 0
    }

    /// X offset of a secondary action, measured from the row's **trailing**
    /// edge. This is the rule the first port inverted.
    static func secondaryOffsetX(index: Int, _ m: Metrics) -> CGFloat {
        -CGFloat(index + 1) * m.actionWidth
    }

    /// The primary sits in the trailing slot. The reference overlays its commit
    /// block on the same slot, so the block is drawn only while leaping —
    /// otherwise the red covers the primary outright.
    static func primaryOffsetX(_ m: Metrics) -> CGFloat { 0 }

    /// How far the rail is translated, `D - e`.
    ///
    /// Measured from the **drawer's** width, not the row's. The reference sizes
    /// the rail to the drawer and translates it by `D - e`; offsetting by
    /// `W - e` instead slides the actions a full row width off screen. This
    /// exists as a named function because that mistake renders as "no drawer at
    /// all", which looks like the gesture not working rather than a layout slip.
    static func railOffsetX(exposed: CGFloat, _ m: Metrics) -> CGFloat {
        m.drawerWidth - exposed
    }

    /// How far the full-width commit block sweeps left. Zero until the drag
    /// passes one action width, then linear — the block is a full-width rect
    /// anchored at `W - A`, not an `A`-wide button that grows.
    static func commitBlockShift(exposed: CGFloat, isLeaping: Bool, _ m: Metrics) -> CGFloat {
        guard isLeaping else { return 0 }
        return max(0, exposed - m.actionWidth)
    }

    /// Counter-translate for the commit label. Without it the label is left
    /// behind at the trailing edge while the red block sweeps underneath, which
    /// is the single most visible way to get this component wrong.
    static func commitLabelOffsetX(exposed: CGFloat, isLeaping: Bool, _ m: Metrics) -> CGFloat {
        guard isLeaping else { return 0 }
        return commitBlockShift(exposed: exposed, isLeaping: true, m)
            - (m.width - m.actionWidth) / 2
    }
}
