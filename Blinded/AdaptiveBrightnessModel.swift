import Foundation

/// Learnable luminance -> brightness mapping.
///
/// The curve is stored as a small set of control points evenly spaced across the
/// luminance domain (0...1) and evaluated by linear interpolation. It cold-starts from the
/// fixed `BrightnessMapper` curve, so behavior is identical until the user corrects it.
///
/// When the user manually overrides brightness at some content luminance, `reinforce`
/// nudges the nearby control points toward the chosen brightness, weighted by a Gaussian
/// kernel in luminance space. This is a simple online local regression: corrections affect
/// the part of the curve near where they were made, and accumulate over time.
struct AdaptiveBrightnessModel: Codable {
    static let binCount = 11   // control points at luminance 0.0, 0.1, ... 1.0

    /// brightnessAtBin[i] is the target brightness at luminance `luminance(forBin: i)`.
    private(set) var brightnessAtBin: [Double]
    /// Kernel width (in luminance units) over which a correction spreads.
    var kernelSigma: Double = 0.15

    static func luminance(forBin i: Int) -> Double {
        Double(i) / Double(binCount - 1)
    }

    /// Cold-start from the fixed curve.
    init(defaultCurve: BrightnessMapper = BrightnessMapper()) {
        brightnessAtBin = (0..<Self.binCount).map { i in
            defaultCurve.brightness(forLuminance: Self.luminance(forBin: i))
        }
    }

    /// Predicted brightness for a content luminance, via linear interpolation.
    func brightness(forLuminance luminance: Double) -> Double {
        let l = max(0, min(1, luminance))
        let pos = l * Double(Self.binCount - 1)
        let lower = Int(pos.rounded(.down))
        let upper = min(lower + 1, Self.binCount - 1)
        let frac = pos - Double(lower)
        let b = brightnessAtBin[lower] * (1 - frac) + brightnessAtBin[upper] * frac
        return max(0, min(1, b))
    }

    /// Snaps the curve so it passes exactly through `(luminance, brightness)` — the user's
    /// correction is adopted in full, so the next prediction at that luminance equals what
    /// they chose (no pull-back). The correction is spread to neighboring control points with
    /// a Gaussian kernel so the curve stays smooth and the change stays local; bins far from
    /// `luminance` are left untouched.
    mutating func reinforce(luminance: Double, brightness: Double) {
        let l = max(0, min(1, luminance))
        let target = max(0, min(1, brightness))
        let delta = target - self.brightness(forLuminance: l)
        let sigma2 = kernelSigma * kernelSigma

        func kernel(_ i: Int) -> Double {
            let d = Self.luminance(forBin: i) - l
            return exp(-(d * d) / sigma2)
        }

        // The interpolated value at `l` reads from the two bracketing bins. Scale the applied
        // correction by their combined weight so the value at `l` lands exactly on `target`.
        let pos = l * Double(Self.binCount - 1)
        let lower = Int(pos.rounded(.down))
        let upper = min(lower + 1, Self.binCount - 1)
        let frac = pos - Double(lower)
        let weightAtL = kernel(lower) * (1 - frac) + kernel(upper) * frac
        guard weightAtL > 1e-9 else { return }
        let scaledDelta = delta / weightAtL

        for i in 0..<Self.binCount {
            brightnessAtBin[i] = max(0, min(1, brightnessAtBin[i] + scaledDelta * kernel(i)))
        }

        // Keep the mapping monotonic (brightness never increases with luminance), pivoting on
        // the corrected bin so the user's chosen value is preserved. A correction at bright
        // content therefore also lifts the backlight for darker content, which is consistent
        // with "darker -> brighter".
        enforceNonIncreasing(pivot: Int((l * Double(Self.binCount - 1)).rounded()))
    }

    /// Forces `brightnessAtBin` to be non-increasing while holding `pivot` fixed.
    private mutating func enforceNonIncreasing(pivot: Int) {
        let p = max(0, min(Self.binCount - 1, pivot))
        if p > 0 {
            for i in stride(from: p - 1, through: 0, by: -1) {
                brightnessAtBin[i] = max(brightnessAtBin[i], brightnessAtBin[i + 1])
            }
        }
        for i in (p + 1)..<Self.binCount {
            brightnessAtBin[i] = min(brightnessAtBin[i], brightnessAtBin[i - 1])
        }
    }
}

// MARK: - Persistence

extension AdaptiveBrightnessModel {
    /// One curve file per display, keyed by a stable display identity (see `Display.persistKey`).
    private static func fileURL(key: String) -> URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Blinded", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return dir.appendingPathComponent("curve-\(safe).json")
    }

    static func loadOrDefault(key: String) -> AdaptiveBrightnessModel {
        guard let data = try? Data(contentsOf: fileURL(key: key)),
              let model = try? JSONDecoder().decode(AdaptiveBrightnessModel.self, from: data),
              model.brightnessAtBin.count == binCount else {
            return AdaptiveBrightnessModel()
        }
        return model
    }

    func save(key: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL(key: key), options: .atomic)
    }

    static func deletePersisted(key: String) {
        try? FileManager.default.removeItem(at: fileURL(key: key))
    }
}
