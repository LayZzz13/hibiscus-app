import CoreGraphics
import UIKit

/// Produces a restrained, fixed neutral correction from a representative still.
/// The result is stored per photo and reused by previews, exports, and every
/// frame of a Live Photo so analysis never introduces temporal flicker.
nonisolated enum EnhanceAnalyzer {
    static func analyze(_ image: UIImage) -> EnhanceAdjustment {
        guard let sample = ImageRenderer.resizedImage(image, maxDimension: 128),
              let cgImage = sample.cgImage else { return .neutral }

        let width = 96
        let height = 96
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .neutral }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var histogram = [Int](repeating: 0, count: 256)
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var colorfulWeight = 0.0
        var count = 0
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index + 3] > 180 {
            let r = Double(pixels[index]) / 255
            let g = Double(pixels[index + 1]) / 255
            let b = Double(pixels[index + 2]) / 255
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            histogram[min(255, max(0, Int((luminance * 255).rounded())))] += 1

            // Very dark/highlight pixels are poor white-balance references.
            // Weight useful midtones more heavily and strongly colorful pixels less.
            let chroma = max(r, g, b) - min(r, g, b)
            let tonalWeight = max(0, 1 - abs(luminance - 0.5) * 1.7)
            let weight = tonalWeight * max(0.18, 1 - chroma * 1.8)
            red += r * weight
            green += g * weight
            blue += b * weight
            colorfulWeight += weight
            count += 1
        }
        guard count > 0 else { return .neutral }

        let low = percentile(histogram, fraction: 0.06)
        let median = percentile(histogram, fraction: 0.50)
        let high = percentile(histogram, fraction: 0.94)
        let safeMedian = max(0.08, median)
        let exposure = clamp(log2(0.46 / safeMedian), -0.42, 0.42)

        let divisor = max(0.001, colorfulWeight)
        let averages = [red / divisor, green / divisor, blue / divisor]
        let neutral = (averages[0] + averages[1] + averages[2]) / 3
        let gains = averages.map { clamp(neutral / max(0.05, $0), 0.91, 1.09) }

        let dynamicRange = high - low
        let contrast = clamp(1 + (0.61 - dynamicRange) * 0.12, 0.975, 1.045)
        let shadows = clamp((0.14 - low) * 0.72, 0, 0.10)
        let highlights = clamp(1 - max(0, high - 0.84) * 0.72, 0.84, 1)

        return EnhanceAdjustment(
            isEnabled: false,
            exposureEV: exposure,
            redGain: gains[0],
            greenGain: gains[1],
            blueGain: gains[2],
            highlightAmount: highlights,
            shadowAmount: shadows,
            contrast: contrast
        )
    }

    private static func percentile(_ histogram: [Int], fraction: Double) -> Double {
        let total = histogram.reduce(0, +)
        guard total > 0 else { return 0.5 }
        let target = Int((Double(total - 1) * fraction).rounded())
        var cumulative = 0
        for (index, value) in histogram.enumerated() {
            cumulative += value
            if cumulative > target { return Double(index) / 255 }
        }
        return 1
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(upper, max(lower, value))
    }
}
