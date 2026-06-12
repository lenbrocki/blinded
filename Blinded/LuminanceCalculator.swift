import CoreVideo

/// Computes the average perceptual luminance of a (small) frame in 0...1.
///
/// Reads the captured `CVPixelBuffer` bytes directly. ScreenCaptureKit delivers a
/// `kCVPixelFormatType_32BGRA` buffer, so we avoid any Core Image / `CGImage` / `CGContext`
/// conversion (that path dominated CPU — a Metal/Core Image round-trip per frame just to
/// average a 64×40 image).
enum LuminanceCalculator {
    static func averageLuminance(of pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0,
              let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }

        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var total = 0.0
        for y in 0 ..< height {
            let row = ptr + y * bytesPerRow
            var x = 0
            while x < width {
                let i = x * 4
                // Memory order for 32BGRA is B, G, R, A.
                let b = Double(row[i])
                let g = Double(row[i + 1])
                let r = Double(row[i + 2])
                total += 0.2126 * r + 0.7152 * g + 0.0722 * b
                x += 1
            }
        }

        return (total / Double(width * height)) / 255.0
    }
}
