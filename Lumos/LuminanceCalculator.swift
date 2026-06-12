import CoreVideo
import Foundation

/// Computes the average *perceptual lightness* (CIE L*) of a (small) frame, normalized to 0...1.
///
/// Reads the captured `CVPixelBuffer` bytes directly. ScreenCaptureKit delivers a
/// `kCVPixelFormatType_32BGRA` buffer, so we avoid any Core Image / `CGImage` / `CGContext`
/// conversion (that path dominated CPU — a Metal/Core Image round-trip per frame just to
/// average a 64×40 image).
///
/// Why L* and not a plain average of the pixel bytes: sRGB bytes are gamma-encoded, so their
/// arithmetic mean isn't proportional to perceived brightness. We instead linearize each pixel,
/// reduce it to relative luminance Y, and map Y to CIELAB **L\*** — a perceptually uniform
/// lightness (0...100) where equal numeric steps look equally different to the eye. Averaging in
/// L* space is what makes Lumos's "constant *perceived* brightness" goal honest. The standard
/// sRGB→linear and Y→L* formulas are used (IEC 61966-2-1 / CIE 1976); L* is rescaled to 0...1.
enum LuminanceCalculator {
    /// sRGB gamma decode (byte 0...255 → linear 0...1), precomputed once to keep the per-pixel
    /// loop free of `pow`.
    private static let sRGBToLinear: [Double] = (0...255).map { i in
        let c = Double(i) / 255.0
        return c > 0.04045 ? pow((c + 0.055) / 1.055, 2.4) : c / 12.92
    }

    /// CIELAB lightness L* (0...100) for a linear relative luminance Y (0...1).
    private static func lightness(_ y: Double) -> Double {
        let f = y > 0.008856 ? cbrt(y) : (7.787 * y + 16.0 / 116.0)
        return 116.0 * f - 16.0
    }

    static func averageLuminance(of pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0,
              let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }

        let lut = sRGBToLinear
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var total = 0.0
        for y in 0 ..< height {
            let row = ptr + y * bytesPerRow
            var x = 0
            while x < width {
                let i = x * 4
                // Memory order for 32BGRA is B, G, R, A. Linearize, reduce to luminance Y,
                // then accumulate perceptual lightness L*.
                let yLinear = 0.2126 * lut[Int(row[i + 2])]
                            + 0.7152 * lut[Int(row[i + 1])]
                            + 0.0722 * lut[Int(row[i])]
                total += lightness(yLinear)
                x += 1
            }
        }

        // Mean L* (0...100) → 0...1.
        return (total / Double(width * height)) / 100.0
    }
}
