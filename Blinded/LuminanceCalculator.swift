import CoreGraphics

/// Computes the average perceptual luminance of a (small) image in 0...1.
/// Stage 1 uses a plain whole-frame average; region weighting can come later.
enum LuminanceCalculator {
    static func averageLuminance(of image: CGImage) -> Double {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return 0 }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 0
        }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var total = 0.0
        var i = 0
        while i < pixels.count {
            let r = Double(pixels[i])
            let g = Double(pixels[i + 1])
            let b = Double(pixels[i + 2])
            total += 0.2126 * r + 0.7152 * g + 0.0722 * b
            i += bytesPerPixel
        }

        let pixelCount = Double(width * height)
        return (total / pixelCount) / 255.0
    }
}
