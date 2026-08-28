import CoreImage
import ImageIO
import UIKit
import Vision

nonisolated enum AccentAnalyzer {
    private struct Bucket {
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var weight = 0.0
        var count = 0
    }

    static func analyze(_ image: UIImage) -> AccentColor {
        // Normalize orientation into a bounded bitmap first. Drawing the full-resolution
        // original here can exceed the memory budget for 48 MP library photos.
        guard let cgImage = analysisCGImage(image, maxDimension: 384) else { return .warmGray }
        let faceRects = detectedFaces(in: cgImage)
        let width = 96
        let height = max(48, min(128, Int(Double(cgImage.height) / Double(cgImage.width) * Double(width))))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .warmGray }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var buckets = [Int: Bucket]()
        var saturationTotal = 0.0
        var validCount = 0

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let r = Double(pixels[index]) / 255
                let g = Double(pixels[index + 1]) / 255
                let b = Double(pixels[index + 2]) / 255
                let hsb = rgbToHSB(red: r, green: g, blue: b)

                guard hsb.brightness > 0.10, hsb.brightness < 0.94, hsb.saturation > 0.10 else { continue }
                validCount += 1
                saturationTotal += hsb.saturation

                let nx = (Double(x) + 0.5) / Double(width)
                let ny = (Double(y) + 0.5) / Double(height)
                let centerDistance = hypot(nx - 0.5, ny - 0.5) / 0.707
                let centerWeight = 1.18 - min(1, centerDistance) * 0.28
                let luminanceWeight = 1 - abs(hsb.brightness - 0.55) * 0.78
                let saturationWeight = 0.35 + pow(hsb.saturation, 0.82)
                let edgeWeight = localContrast(pixels: pixels, x: x, y: y, width: width, height: height, r: r, g: g, b: b)
                let inFace = faceRects.contains { $0.contains(CGPoint(x: nx, y: 1 - ny)) }
                let faceWeight = inFace ? 0.42 : 1.0
                let skinLike = (hsb.hue < 0.12 || hsb.hue > 0.97) && hsb.saturation < 0.72
                let skinWeight = skinLike ? 0.78 : 1.0
                let weight = centerWeight * luminanceWeight * saturationWeight * edgeWeight * faceWeight * skinWeight

                let hueBin = min(17, Int(hsb.hue * 18))
                let satBin = min(3, Int(hsb.saturation * 4))
                let lightBin = min(3, Int(hsb.brightness * 4))
                let key = hueBin * 100 + satBin * 10 + lightBin
                var bucket = buckets[key, default: Bucket()]
                bucket.red += r * weight
                bucket.green += g * weight
                bucket.blue += b * weight
                bucket.weight += weight
                bucket.count += 1
                buckets[key] = bucket
            }
        }

        guard validCount > width * height / 35,
              saturationTotal / Double(max(1, validCount)) > 0.16 else {
            return averageLuminance(pixels) > 0.53 ? .coolGray : .warmGray
        }

        let minimumPopulation = max(5, validCount / 220)
        let winner = buckets.values
            .filter { $0.count >= minimumPopulation }
            .max { lhs, rhs in
                let lhsScore = lhs.weight * log2(Double(lhs.count) + 2)
                let rhsScore = rhs.weight * log2(Double(rhs.count) + 2)
                return lhsScore < rhsScore
            }

        guard let winner, winner.weight > 0 else { return .warmGray }
        return AccentColor(
            red: min(1, max(0, winner.red / winner.weight)),
            green: min(1, max(0, winner.green / winner.weight)),
            blue: min(1, max(0, winner.blue / winner.weight))
        )
    }

    static func downsample(_ data: Data, maxDimension: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension)
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: image)
    }

    private static func analysisCGImage(_ image: UIImage, maxDimension: CGFloat) -> CGImage? {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(sourceSize.width, sourceSize.height))
        let size = CGSize(
            width: max(1, floor(sourceSize.width * scale)),
            height: max(1, floor(sourceSize.height * scale))
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }

    private static func detectedFaces(in image: CGImage) -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try? handler.perform([request])
        return request.results?.map(\.boundingBox) ?? []
    }

    private static func localContrast(
        pixels: [UInt8], x: Int, y: Int, width: Int, height: Int,
        r: Double, g: Double, b: Double
    ) -> Double {
        let sampleX = min(width - 1, x + 3)
        let sampleY = min(height - 1, y + 3)
        let index = (sampleY * width + sampleX) * 4
        let rr = Double(pixels[index]) / 255
        let gg = Double(pixels[index + 1]) / 255
        let bb = Double(pixels[index + 2]) / 255
        let difference = abs(r - rr) + abs(g - gg) + abs(b - bb)
        return 0.92 + min(0.65, difference * 0.55)
    }

    private static func rgbToHSB(red: Double, green: Double, blue: Double) -> (hue: Double, saturation: Double, brightness: Double) {
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue
        let saturation = maxValue == 0 ? 0 : delta / maxValue
        var hue = 0.0
        if delta > 0 {
            if maxValue == red {
                hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxValue == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, saturation, maxValue)
    }

    private static func averageLuminance(_ pixels: [UInt8]) -> Double {
        var sum = 0.0
        var count = 0
        for index in stride(from: 0, to: pixels.count, by: 16) {
            sum += Double(pixels[index]) * 0.2126
                + Double(pixels[index + 1]) * 0.7152
                + Double(pixels[index + 2]) * 0.0722
            count += 1
        }
        return sum / Double(max(1, count)) / 255
    }
}
