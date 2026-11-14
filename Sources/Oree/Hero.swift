import ImageIO
import SwiftUI

/// The picture across the top of the desktop, printed as a grid of dots:
/// each dot's brightness is rounded up or down against a repeating 8×8
/// threshold pattern, which gives the picture its grain. Toward its foot a soft vignette
/// sinks it into the ground while its dots thin out along a gently rolling
/// edge, so picture and dashboard read as one surface.
struct HeroView: View {
    let imageURL: URL?
    @State private var rendered: CGImage?

    /// The size of one dot of the grid, in points.
    private static let cell: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let rendered {
                    Image(decorative: rendered, scale: 1)
                        .interpolation(.none)
                        .resizable()
                }
            }
            .task(id: RenderKey(url: imageURL, size: geometry.size)) {
                let columns = Int(geometry.size.width / Self.cell)
                let rows = Int(geometry.size.height / Self.cell)
                let url = imageURL
                rendered = await Task.detached(priority: .userInitiated) {
                    guard let url, let source = Dither.load(url) else { return nil }
                    return Dither.render(source, columns: columns, rows: rows)
                }.value
            }
        }
    }

    private struct RenderKey: Equatable {
        let url: URL?
        let size: CGSize
    }
}

enum Dither {
    /// Where, down the picture, the vignette begins to darken it.
    private static let shadeStart: Float = 0.3
    /// Where its dots begin to thin out.
    private static let dissolveStart: Float = 0.46
    /// How many shades of brightness the dots are rounded to.
    private static let levels: Float = 5
    /// How much of the grain shows over the smooth picture.
    private static let grain: Float = 0.45
    /// The picture is brought down to sit in a dark interface.
    private static let dim: Float = 0.82

    static func load(_ url: URL, maxPixel: Int = 2400) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The 8×8 Bayer threshold at a dot, in 0..<1.
    static func threshold(_ x: Int, _ y: Int) -> Float {
        let xc = (x ^ y) & 7
        let yc = y & 7
        var value = 0
        var bit = 0
        for mask in stride(from: 2, through: 0, by: -1) {
            value |= ((yc >> mask) & 1) << bit
            bit += 1
            value |= ((xc >> mask) & 1) << bit
            bit += 1
        }
        return (Float(value) + 0.5) / 64
    }

    /// 0 below `from`, 1 above `to`, eased in between.
    private static func smooth(_ from: Float, _ to: Float, _ value: Float) -> Float {
        let t = max(0, min(1, (value - from) / (to - from)))
        return t * t * (3 - 2 * t)
    }

    /// One pixel per dot; the view scales it up with hard edges.
    static func render(_ source: CGImage, columns: Int, rows: Int) -> CGImage? {
        guard columns > 0, rows > 0,
              let context = CGContext(
                  data: nil,
                  width: columns,
                  height: rows,
                  bitsPerComponent: 8,
                  bytesPerRow: columns * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        // Cover the band, like a wallpaper set to fill.
        let scale = max(CGFloat(columns) / CGFloat(source.width), CGFloat(rows) / CGFloat(source.height))
        let width = CGFloat(source.width) * scale
        let height = CGFloat(source.height) * scale
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(
            x: (CGFloat(columns) - width) / 2,
            y: (CGFloat(rows) - height) / 2,
            width: width,
            height: height
        ))

        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: columns * rows * 4)
        let ground = Theme.groundRGB

        for y in 0..<rows {
            let down = Float(y) / Float(max(1, rows - 1))
            for x in 0..<columns {
                let across = Float(x) / Float(max(1, columns - 1))
                let offset = (y * columns + x) * 4
                let limit = threshold(x, y)
                // The foot is not a straight line: it rolls a little.
                let level = down + 0.03 * sin(across * 8.5) + 0.018 * sin(across * 21 + 1.7)
                // How far the dots have thinned, easing in so the first ones
                // to go are barely missed.
                let dissolve = pow(smooth(dissolveStart, 1, level), 1.35)
                guard dissolve < limit else {
                    // Gone: whatever lies behind the picture shows through.
                    pixels[offset] = 0
                    pixels[offset + 1] = 0
                    pixels[offset + 2] = 0
                    pixels[offset + 3] = 0
                    continue
                }
                var colour = SIMD3(
                    Float(pixels[offset]),
                    Float(pixels[offset + 1]),
                    Float(pixels[offset + 2])
                ) / 255 * dim
                // Only brightness is rounded; the colour itself is left alone.
                let light = max(0.001, colour.x * 0.299 + colour.y * 0.587 + colour.z * 0.114)
                let stepped = (light * levels + limit).rounded(.down) / levels
                colour *= 1 + (stepped / light - 1) * grain
                // The vignette: deeper toward the foot and the lower corners.
                let side = abs(across - 0.5) * 2
                let shade = min(1, smooth(shadeStart, 1.08, level) * 0.9 + side * side * 0.25 * down)
                colour += (ground - colour) * shade
                pixels[offset] = UInt8(max(0, min(255, colour.x * 255)))
                pixels[offset + 1] = UInt8(max(0, min(255, colour.y * 255)))
                pixels[offset + 2] = UInt8(max(0, min(255, colour.z * 255)))
                pixels[offset + 3] = 255
            }
        }
        return context.makeImage()
    }
}
