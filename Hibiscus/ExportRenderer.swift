import CoreGraphics
import ImageIO
import PencilKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

nonisolated enum HibiscusExportFormat: String, CaseIterable, Identifiable, Sendable {
    case photo = "Photo"
    case polaroid = "Polaroid"
    case palette = "Palette"
    case colorPads = "Color Pads"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .photo: "photo"
        case .polaroid: "rectangle.portrait"
        case .palette: "swatchpalette"
        case .colorPads: "square.grid.2x2"
        }
    }
}

nonisolated struct PolaroidComposition: Sendable {
    var drawingData: Data
    var drawingCanvasSize: CGSize
    var cropScale: Double
    var cropOffset: CGPoint
    var showsMetadata: Bool
    var showsMark: Bool
    var includesLocation: Bool

    static let empty = PolaroidComposition(
        drawingData: Data(),
        drawingCanvasSize: .zero,
        cropScale: 1,
        cropOffset: .zero,
        showsMetadata: false,
        showsMark: true,
        includesLocation: true
    )
}

nonisolated struct PaletteComposition: Sendable {
    var selectedIndices: [Int]
    var showsHexCodes: Bool

    static let standard = PaletteComposition(selectedIndices: Array(0..<5), showsHexCodes: false)
}

nonisolated enum PhotoMetadataExtractor {
    static func metadata(from data: Data) -> PhotoMetadata {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return PhotoMetadata()
        }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let dateString = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifDateTimeDigitized] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)
        let date = dateString.flatMap(parseDate)

        var location: String?
        var latitude: Double?
        var longitude: Double?
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let latitudeNumber = gps[kCGImagePropertyGPSLatitude] as? NSNumber,
           let longitudeNumber = gps[kCGImagePropertyGPSLongitude] as? NSNumber {
            let isSouth = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() == "S"
            let isWest = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() == "W"
            latitude = isSouth ? -latitudeNumber.doubleValue : latitudeNumber.doubleValue
            longitude = isWest ? -longitudeNumber.doubleValue : longitudeNumber.doubleValue
            let northSouth = (latitude ?? 0) >= 0 ? "N" : "S"
            let eastWest = (longitude ?? 0) >= 0 ? "E" : "W"
            location = String(
                format: "%.4f°%@ · %.4f°%@",
                abs(latitude ?? 0), northSouth, abs(longitude ?? 0), eastWest
            )
        }

        return PhotoMetadata(
            date: date,
            location: location,
            cameraCharacter: nil,
            latitude: latitude,
            longitude: longitude,
            cameraMake: tiff?[kCGImagePropertyTIFFMake] as? String,
            cameraModel: tiff?[kCGImagePropertyTIFFModel] as? String,
            lensModel: exif?[kCGImagePropertyExifLensModel] as? String
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: value)
    }
}

nonisolated enum PaletteAnalyzer {
    static func colors(from image: UIImage, count: Int = 5) -> [AccentColor] {
        guard let sample = ImageRenderer.resizedImage(image, maxDimension: 72),
              let cgImage = sample.cgImage else { return [.warmGray, .coolGray] }

        let width = 64
        let height = 64
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [.warmGray, .coolGray] }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        struct Bucket {
            var count = 0
            var red = 0.0
            var green = 0.0
            var blue = 0.0
        }
        var buckets: [Int: Bucket] = [:]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            guard pixels[index + 3] > 180 else { continue }
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            let key = (Int(red * 15) << 8) | (Int(green * 15) << 4) | Int(blue * 15)
            var bucket = buckets[key] ?? Bucket()
            bucket.count += 1
            bucket.red += red
            bucket.green += green
            bucket.blue += blue
            buckets[key] = bucket
        }

        let candidates = buckets.values.sorted { lhs, rhs in
            let lhsAverage = (lhs.red + lhs.green + lhs.blue) / Double(max(1, lhs.count))
            let rhsAverage = (rhs.red + rhs.green + rhs.blue) / Double(max(1, rhs.count))
            let lhsScore = Double(lhs.count) * (0.78 + 0.22 * lhsAverage)
            let rhsScore = Double(rhs.count) * (0.78 + 0.22 * rhsAverage)
            return lhsScore > rhsScore
        }

        var result: [AccentColor] = []
        for bucket in candidates {
            let divisor = Double(max(1, bucket.count))
            let candidate = AccentColor(
                red: bucket.red / divisor,
                green: bucket.green / divisor,
                blue: bucket.blue / divisor
            )
            guard result.allSatisfy({ colorDistance($0, candidate) > 0.13 }) else { continue }
            result.append(candidate)
            if result.count == count { break }
        }
        return result.isEmpty ? [.warmGray] : result
    }

    private static func colorDistance(_ lhs: AccentColor, _ rhs: AccentColor) -> Double {
        sqrt(pow(lhs.red - rhs.red, 2) + pow(lhs.green - rhs.green, 2) + pow(lhs.blue - rhs.blue, 2))
    }
}

nonisolated enum HibiscusExportRenderer {
    static func jpegData(
        for image: UIImage,
        metadata: PhotoMetadata,
        preservesMetadata: Bool,
        includesLocation: Bool
    ) -> Data? {
        guard preservesMetadata, let cgImage = image.cgImage else {
            return image.jpegData(compressionQuality: 0.96)
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return image.jpegData(compressionQuality: 0.96) }

        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.96
        ]
        var tiff: [CFString: Any] = [:]
        if let make = metadata.cameraMake { tiff[kCGImagePropertyTIFFMake] = make }
        if let model = metadata.cameraModel { tiff[kCGImagePropertyTIFFModel] = model }
        if !tiff.isEmpty { properties[kCGImagePropertyTIFFDictionary] = tiff }

        var exif: [CFString: Any] = [:]
        if let date = metadata.date {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            exif[kCGImagePropertyExifDateTimeOriginal] = formatter.string(from: date)
        }
        if let lens = metadata.lensModel { exif[kCGImagePropertyExifLensModel] = lens }
        if !exif.isEmpty { properties[kCGImagePropertyExifDictionary] = exif }

        if includesLocation, let latitude = metadata.latitude, let longitude = metadata.longitude {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: abs(latitude),
                kCGImagePropertyGPSLatitudeRef: latitude >= 0 ? "N" : "S",
                kCGImagePropertyGPSLongitude: abs(longitude),
                kCGImagePropertyGPSLongitudeRef: longitude >= 0 ? "E" : "W"
            ]
        }

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func render(
        editedImage: UIImage,
        format: HibiscusExportFormat,
        settings: GradeSettings,
        metadata: PhotoMetadata,
        polaroidComposition: PolaroidComposition = .empty,
        paletteComposition: PaletteComposition = .standard
    ) -> UIImage {
        switch format {
        case .photo:
            editedImage
        case .polaroid:
            polaroid(
                image: editedImage,
                settings: settings,
                metadata: metadata,
                composition: polaroidComposition
            )
        case .palette:
            palette(image: editedImage, composition: paletteComposition)
        case .colorPads:
            colorPads(image: editedImage, settings: settings)
        }
    }

    private static func colorPads(image: UIImage, settings: GradeSettings) -> UIImage {
        let width: CGFloat = 1800
        let ratio = image.size.width / max(1, image.size.height)
        let photoHeight = max(width * 0.58, min(width * 1.65, width / max(0.01, ratio)))
        let controlsHeight: CGFloat = 760
        let canvas = CGSize(width: width, height: photoHeight + controlsHeight)
        let padSize: CGFloat = 560
        let gap: CGFloat = 80
        let firstX = (width - padSize * 2 - gap) / 2
        let padY = photoHeight + 64
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor(red: 0.965, green: 0.958, blue: 0.938, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            drawAspectFit(image, in: CGRect(x: 0, y: 0, width: width, height: photoHeight))

            let styleRect = CGRect(x: firstX, y: padY, width: padSize, height: padSize)
            let accentRect = CGRect(x: firstX + padSize + gap, y: padY, width: padSize, height: padSize)
            drawGradePad(
                in: styleRect,
                colors: stylePadColors(for: settings.style),
                warmCornerColor: mix(UIColor(settings.style.tint), with: .systemOrange, amount: 0.28),
                toneTopAlpha: 0.78,
                toneClearLocation: 0.42,
                toneBottomAlpha: 0.88,
                point: settings.stylePoint,
                context: context.cgContext
            )
            drawGradePad(
                in: accentRect,
                colors: accentPadColors(for: settings.accent),
                warmCornerColor: nil,
                toneTopAlpha: 0.72,
                toneClearLocation: 0.40,
                toneBottomAlpha: 0.86,
                point: settings.accentPoint,
                context: context.cgContext
            )

            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 42, weight: .semibold),
                .foregroundColor: UIColor(white: 0.14, alpha: 0.88)
            ]
            drawCentered(settings.style.rawValue, beneath: styleRect, attributes: labelAttributes)
            drawAccentLabel(
                beneath: accentRect,
                accent: settings.accent,
                attributes: labelAttributes,
                context: context.cgContext
            )
        }
    }

    private static func polaroid(
        image: UIImage,
        settings: GradeSettings,
        metadata: PhotoMetadata,
        composition: PolaroidComposition
    ) -> UIImage {
        let canvas = CGSize(width: 1800, height: 2320)
        let photoRect = CGRect(x: 90, y: 90, width: 1620, height: 1620)
        let lowerRect = CGRect(x: 90, y: 1740, width: 1620, height: 490)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor(red: 0.955, green: 0.947, blue: 0.918, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            drawAspectFill(
                image,
                in: photoRect,
                scale: CGFloat(composition.cropScale),
                offset: composition.cropOffset
            )

            if composition.showsMetadata {
                drawPolaroidMetadata(
                    metadata,
                    settings: settings,
                    includesLocation: composition.includesLocation,
                    in: lowerRect,
                    context: context.cgContext
                )
            }

            if composition.showsMark {
                let markCenterX = composition.showsMetadata ? lowerRect.maxX - 180 : lowerRect.midX
                let markRect = CGRect(x: markCenterX - 66, y: lowerRect.midY - 66, width: 132, height: 132)
                drawAppIcon(in: markRect, context: context.cgContext)
                let brand = "Hibiscus"
                let brandAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 48, weight: .semibold),
                    .foregroundColor: UIColor(white: 0.17, alpha: 0.72)
                ]
                let brandSize = brand.size(withAttributes: brandAttributes)
                brand.draw(
                    at: CGPoint(x: markCenterX - brandSize.width / 2, y: markRect.maxY + 22),
                    withAttributes: brandAttributes
                )
            }

            drawPencilDrawing(composition, in: canvas)
        }
    }

    private static func palette(image: UIImage, composition: PaletteComposition) -> UIImage {
        let width: CGFloat = 1800
        let ratio = image.size.width / max(1, image.size.height)
        let photoHeight = max(width * 0.55, min(width * 1.8, width / max(0.01, ratio)))
        let colorHeight: CGFloat = 150
        let brandHeight: CGFloat = 180
        let footerHeight = colorHeight + brandHeight
        let canvas = CGSize(width: width, height: photoHeight + footerHeight)
        let candidates = PaletteAnalyzer.colors(from: image, count: 5)
        var colors = composition.selectedIndices
            .sorted()
            .compactMap { candidates.indices.contains($0) ? candidates[$0] : nil }
        if colors.isEmpty { colors = Array(candidates.prefix(1)) }
        let hexTextColor = paletteHexTextColor(for: colors)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor(red: 0.965, green: 0.958, blue: 0.938, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            drawAspectFit(image, in: CGRect(x: 0, y: 0, width: width, height: photoHeight))

            let blockWidth = width / CGFloat(colors.count)
            for (index, color) in colors.enumerated() {
                let uiColor = UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
                uiColor.setFill()
                let blockRect = CGRect(
                    x: CGFloat(index) * blockWidth,
                    y: photoHeight,
                    width: blockWidth + 1,
                    height: colorHeight
                )
                context.cgContext.fill(blockRect)
                if composition.showsHexCodes {
                    let hex = hexString(for: color)
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.monospacedSystemFont(ofSize: 30, weight: .semibold),
                        .foregroundColor: hexTextColor
                    ]
                    let textSize = hex.size(withAttributes: attributes)
                    hex.draw(
                        at: CGPoint(x: blockRect.midX - textSize.width / 2, y: blockRect.midY - textSize.height / 2),
                        withAttributes: attributes
                    )
                }
            }

            let brandArea = CGRect(x: 0, y: photoHeight + colorHeight, width: width, height: brandHeight)
            let markRect = CGRect(x: brandArea.midX - 38, y: brandArea.minY + 20, width: 76, height: 76)
            drawAppIcon(in: markRect, context: context.cgContext)
            let brand = "Hibiscus"
            let brandAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34, weight: .semibold),
                .foregroundColor: UIColor(white: 0.17, alpha: 0.72)
            ]
            let brandSize = brand.size(withAttributes: brandAttributes)
            brand.draw(
                at: CGPoint(x: brandArea.midX - brandSize.width / 2, y: markRect.maxY + 12),
                withAttributes: brandAttributes
            )
        }
    }

    private static func drawAspectFit(_ image: UIImage, in rect: CGRect) {
        let ratio = image.size.width / max(1, image.size.height)
        let targetRatio = rect.width / rect.height
        let drawRect: CGRect
        if ratio > targetRatio {
            let height = rect.width / ratio
            drawRect = CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        } else {
            let width = rect.height * ratio
            drawRect = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
        }
        image.draw(in: drawRect)
    }

    private static func drawPolaroidMetadata(
        _ metadata: PhotoMetadata,
        settings: GradeSettings,
        includesLocation: Bool,
        in rect: CGRect,
        context: CGContext
    ) {
        var lines: [String] = []
        if let date = metadata.date {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMM d yyyy · HH:mm"
            lines.append(formatter.string(from: date).uppercased())
        }
        if includesLocation, let location = metadata.location {
            lines.append(location.uppercased())
        }
        let camera = metadata.cameraCharacter.map { "\($0.glyph) \($0.name.uppercased()) · " } ?? ""
        lines.append("\(camera)\(settings.style.rawValue.uppercased())")
        let hardware = [metadata.cameraMake, metadata.cameraModel, metadata.lensModel]
            .compactMap({ $0 })
            .joined(separator: " · ")
        if !hardware.isEmpty {
            lines.append(hardware.uppercased())
        }

        context.saveGState()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 29, weight: .medium),
            .foregroundColor: UIColor(white: 0.22, alpha: 0.74)
        ]
        lines.prefix(4).joined(separator: "\n").draw(
            in: CGRect(x: rect.minX + 38, y: rect.minY + 150, width: rect.width - 430, height: 230),
            withAttributes: attributes
        )
        context.restoreGState()
    }

    private static func stylePadColors(for style: GradeStyle) -> [UIColor] {
        let tint = UIColor(style.tint)
        return [UIColor(white: 0.56, alpha: 1), tint.withAlphaComponent(0.76), tint]
    }

    private static func accentPadColors(for accent: AccentColor) -> [UIColor] {
        let base = UIColor(red: accent.red, green: accent.green, blue: accent.blue, alpha: 1)
        return [mix(base, with: .systemBlue, amount: 0.42), base, mix(base, with: .systemOrange, amount: 0.38)]
    }

    private static func drawGradePad(
        in rect: CGRect,
        colors: [UIColor],
        warmCornerColor: UIColor?,
        toneTopAlpha: CGFloat,
        toneClearLocation: CGFloat,
        toneBottomAlpha: CGFloat,
        point: CGPoint,
        context: CGContext
    ) {
        context.saveGState()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.width * (15 / 175))
        path.addClip()

        if let horizontal = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors.map(\.cgColor) as CFArray,
            locations: [0, 0.5, 1]
        ) {
            context.drawLinearGradient(
                horizontal,
                start: CGPoint(x: rect.minX, y: rect.midY),
                end: CGPoint(x: rect.maxX, y: rect.midY),
                options: []
            )
        }
        if let warmCornerColor,
           let corner = CGGradient(
               colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
               colors: [warmCornerColor.withAlphaComponent(0.54).cgColor, UIColor.clear.cgColor] as CFArray,
               locations: [0, 1]
           ) {
            context.drawRadialGradient(
                corner,
                startCenter: CGPoint(x: rect.maxX, y: rect.maxY),
                startRadius: 0,
                endCenter: CGPoint(x: rect.maxX, y: rect.maxY),
                endRadius: rect.width * (150 / 175),
                options: []
            )
        }
        if let tone = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [
                UIColor.white.withAlphaComponent(toneTopAlpha).cgColor,
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(toneBottomAlpha).cgColor
            ] as CFArray,
            locations: [0, toneClearLocation, 1]
        ) {
            context.drawLinearGradient(
                tone,
                start: CGPoint(x: rect.midX, y: rect.minY),
                end: CGPoint(x: rect.midX, y: rect.maxY),
                options: []
            )
        }

        let inset = rect.width * 0.09
        for row in 0..<11 {
            for column in 0..<11 {
                let x = rect.minX + inset + (rect.width - inset * 2) * CGFloat(column) / 10
                let y = rect.minY + inset + (rect.height - inset * 2) * CGFloat(row) / 10
                let radius = rect.width * (row > 7 ? 1.65 / 175 : 1.35 / 175)
                UIColor.white.withAlphaComponent(0.36 + CGFloat(row) / 10 * 0.42).setFill()
                context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            }
        }

        let centerMarkerSize = rect.width * (8 / 175)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.34).cgColor)
        context.setLineWidth(max(1, rect.width / 175))
        context.strokeEllipse(in: CGRect(
            x: rect.midX - centerMarkerSize / 2,
            y: rect.midY - centerMarkerSize / 2,
            width: centerMarkerSize,
            height: centerMarkerSize
        ))
        context.restoreGState()

        let controlSize = rect.width * (22 / 175)
        let controlCenter = CGPoint(
            x: rect.minX + controlSize / 2 + min(1, max(0, point.x)) * (rect.width - controlSize),
            y: rect.minY + controlSize / 2 + min(1, max(0, point.y)) * (rect.height - controlSize)
        )
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: rect.width * (2 / 175)),
            blur: rect.width * (5 / 175),
            color: UIColor.black.withAlphaComponent(0.50).cgColor
        )
        UIColor.white.setFill()
        context.fillEllipse(in: CGRect(
            x: controlCenter.x - controlSize / 2,
            y: controlCenter.y - controlSize / 2,
            width: controlSize,
            height: controlSize
        ))
        context.restoreGState()
        context.setStrokeColor(UIColor.black.withAlphaComponent(0.34).cgColor)
        context.setLineWidth(max(1, rect.width / 175))
        context.strokeEllipse(in: CGRect(
            x: controlCenter.x - controlSize / 2,
            y: controlCenter.y - controlSize / 2,
            width: controlSize,
            height: controlSize
        ))
    }

    private static func drawCentered(
        _ string: String,
        beneath rect: CGRect,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let size = string.size(withAttributes: attributes)
        string.draw(
            at: CGPoint(x: rect.midX - size.width / 2, y: rect.maxY + 24),
            withAttributes: attributes
        )
    }

    private static func drawAccentLabel(
        beneath rect: CGRect,
        accent: AccentColor,
        attributes: [NSAttributedString.Key: Any],
        context: CGContext
    ) {
        let label = "Accent"
        let labelSize = label.size(withAttributes: attributes)
        let chipSize: CGFloat = 32
        let gap: CGFloat = 14
        let totalWidth = labelSize.width + gap + chipSize
        let originX = rect.midX - totalWidth / 2
        let originY = rect.maxY + 24
        label.draw(at: CGPoint(x: originX, y: originY), withAttributes: attributes)

        UIColor(red: accent.red, green: accent.green, blue: accent.blue, alpha: 1).setFill()
        context.fillEllipse(in: CGRect(
            x: originX + labelSize.width + gap,
            y: originY + (labelSize.height - chipSize) / 2,
            width: chipSize,
            height: chipSize
        ))
    }

    private static func mix(_ lhs: UIColor, with rhs: UIColor, amount: CGFloat) -> UIColor {
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
        lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)
        return UIColor(
            red: lr + (rr - lr) * amount,
            green: lg + (rg - lg) * amount,
            blue: lb + (rb - lb) * amount,
            alpha: 1
        )
    }

    private static func hexString(for color: AccentColor) -> String {
        String(
            format: "#%02X%02X%02X",
            Int(min(1, max(0, color.red)) * 255),
            Int(min(1, max(0, color.green)) * 255),
            Int(min(1, max(0, color.blue)) * 255)
        )
    }

    static func paletteHexTextColor(for colors: [AccentColor]) -> UIColor {
        guard !colors.isEmpty else { return UIColor(white: 0.08, alpha: 0.84) }
        let averageLuminance = colors.reduce(0.0) { result, color in
            result + 0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
        } / Double(colors.count)
        return averageLuminance >= 0.42
            ? UIColor(white: 0.08, alpha: 0.84)
            : UIColor(white: 1, alpha: 0.92)
    }

    private static func drawAspectFill(
        _ image: UIImage,
        in rect: CGRect,
        scale: CGFloat = 1,
        offset: CGPoint = .zero
    ) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let sourceRatio = image.size.width / max(1, image.size.height)
        let targetRatio = rect.width / rect.height
        var drawRect = rect
        if sourceRatio > targetRatio {
            drawRect.size.width = rect.height * sourceRatio
            drawRect.origin.x = rect.midX - drawRect.width / 2
        } else {
            drawRect.size.height = rect.width / sourceRatio
            drawRect.origin.y = rect.midY - drawRect.height / 2
        }
        let safeScale = max(1, min(3, scale))
        drawRect = CGRect(
            x: rect.midX - drawRect.width * safeScale / 2 + offset.x * rect.width,
            y: rect.midY - drawRect.height * safeScale / 2 + offset.y * rect.height,
            width: drawRect.width * safeScale,
            height: drawRect.height * safeScale
        )
        context.saveGState()
        context.clip(to: rect)
        image.draw(in: drawRect)
        context.restoreGState()
    }

    private static func drawPencilDrawing(_ composition: PolaroidComposition, in canvas: CGSize) {
        guard !composition.drawingData.isEmpty,
              composition.drawingCanvasSize.width > 0,
              composition.drawingCanvasSize.height > 0,
              let drawing = try? PKDrawing(data: composition.drawingData) else { return }
        let scale = canvas.width / composition.drawingCanvasSize.width
        drawing.image(
            from: CGRect(origin: .zero, size: composition.drawingCanvasSize),
            scale: scale
        ).draw(in: CGRect(origin: .zero, size: canvas))
    }

    private static func drawAppIcon(in rect: CGRect, context: CGContext) {
        guard let icon = HibiscusBrand.appIcon() else { return }
        context.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.width * 0.22).addClip()
        icon.draw(in: rect)
        context.restoreGState()
    }
}

nonisolated enum HibiscusBrand {
    static func appIcon() -> UIImage? {
        let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any]
        let primaryIcon = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let iconFiles = primaryIcon?["CFBundleIconFiles"] as? [String] ?? []
        for name in iconFiles.reversed() {
            if let image = UIImage(named: name) { return image }
            if let path = Bundle.main.path(forResource: name, ofType: nil),
               let image = UIImage(contentsOfFile: path) { return image }
        }
        return ["AppIcon", "AppIcon60x60", "AppIcon76x76"]
            .lazy
            .compactMap(UIImage.init(named:))
            .first
    }
}
