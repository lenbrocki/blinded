import Foundation

/// Fixed luminance -> brightness mapping for stage 1. Pure logic with no system
/// dependencies, so a learned per-user model can replace it behind the same interface
/// in a later stage.
///
/// Inverse curve: dark content (low luminance) -> high backlight; bright content -> low
/// backlight. `gamma < 1` keeps mid-tones from dimming too aggressively.
struct BrightnessMapper {
    var minBrightness: Double = 0.25
    var maxBrightness: Double = 1.0
    var gamma: Double = 0.7

    /// Maps content luminance (0...1) to a target backlight level (minBrightness...maxBrightness).
    func brightness(forLuminance luminance: Double) -> Double {
        let l = max(0, min(1, luminance))
        let curve = pow(l, gamma)
        return maxBrightness - (maxBrightness - minBrightness) * curve
    }
}
