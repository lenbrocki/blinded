import Foundation
import QuartzCore

/// Rejects transient luminance (window/space-swipe animations, brief flashes) so the
/// backlight retargets only to *settled* content. It tracks a `committed` luminance and
/// only advances it once a new luminance has held steady for `settleTime`. While content is
/// still animating, consecutive readings keep differing by more than `settleBand`, so nothing
/// commits and the backlight does not chase the animation.
struct LuminanceStabilizer {
    var settleTime: CFTimeInterval = 0.05  // how long a value must hold to be accepted
    var settleBand: Double = 0.03          // "still moving" if consecutive readings differ by more
    var noiseBand: Double = 0.015          // ignore differences from committed below this

    private(set) var committed: Double
    private var pending: Double?
    private var pendingSince: CFTimeInterval = 0

    init(initial: Double = -1) {
        // -1 forces the first real reading to be treated as a change and committed.
        committed = initial
    }

    /// Feeds a new reading. Returns true when `committed` advances to a newly settled value.
    mutating func update(luminance: Double, now: CFTimeInterval) -> Bool {
        if abs(luminance - committed) <= noiseBand {
            pending = nil
            return false
        }
        if let pending, abs(luminance - pending) <= settleBand {
            if now - pendingSince >= settleTime {
                committed = luminance
                self.pending = nil
                return true
            }
            return false
        }
        // Still moving (or first divergence) — restart the settle window.
        pending = luminance
        pendingSince = now
        return false
    }
}
