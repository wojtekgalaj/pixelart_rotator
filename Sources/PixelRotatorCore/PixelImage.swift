import CoreGraphics
import Foundation

public struct RGBA: Sendable, Equatable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public static let clear = RGBA(r: 0, g: 0, b: 0, a: 0)

    public var isOpaque: Bool { a >= 16 }

    public func premultiplied() -> RGBA {
        if a == 255 || a == 0 { return self }
        let scale = UInt16(a)
        return RGBA(
            r: UInt8(UInt16(r) * scale / 255),
            g: UInt8(UInt16(g) * scale / 255),
            b: UInt8(UInt16(b) * scale / 255),
            a: a
        )
    }
}

public struct PixelImage: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, fill: RGBA = .clear) {
        self.width = max(1, width)
        self.height = max(1, height)
        let count = self.width * self.height * 4
        self.pixels = [UInt8](repeating: 0, count: count)
        if fill != .clear {
            for i in stride(from: 0, to: count, by: 4) {
                pixels[i] = fill.r
                pixels[i + 1] = fill.g
                pixels[i + 2] = fill.b
                pixels[i + 3] = fill.a
            }
        }
    }

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        if pixels.count == width * height * 4 {
            self.pixels = pixels
        } else {
            self.pixels = [UInt8](repeating: 0, count: width * height * 4)
        }
    }

    public func index(_ x: Int, _ y: Int) -> Int {
        (y * width + x) * 4
    }

    public func contains(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height
    }

    public func color(x: Int, y: Int) -> RGBA {
        guard contains(x, y) else { return .clear }
        let i = index(x, y)
        return RGBA(r: pixels[i], g: pixels[i + 1], b: pixels[i + 2], a: pixels[i + 3])
    }

    public mutating func set(x: Int, y: Int, _ color: RGBA) {
        guard contains(x, y) else { return }
        let i = index(x, y)
        pixels[i] = color.r
        pixels[i + 1] = color.g
        pixels[i + 2] = color.b
        pixels[i + 3] = color.a
    }

    public mutating func fill(x: Int, y: Int, w: Int, h: Int, _ color: RGBA) {
        let x1 = max(0, x)
        let y1 = max(0, y)
        let x2 = min(width, x + w)
        let y2 = min(height, y + h)
        guard x1 < x2, y1 < y2 else { return }
        for py in y1..<y2 {
            for px in x1..<x2 {
                set(x: px, y: py, color)
            }
        }
    }

    public func flippedHorizontally() -> PixelImage {
        var copy = PixelImage(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                copy.set(x: width - 1 - x, y: y, color(x: x, y: y))
            }
        }
        return copy
    }

    public func hasTransparency() -> Bool {
        for i in stride(from: 3, to: pixels.count, by: 4) where pixels[i] < 250 {
            return true
        }
        return false
    }

    /// Drops pixels close to the top-left color. Used when a drawing has a solid backdrop instead of alpha.
    public func keyingOutCorner(tolerance: Int) -> PixelImage {
        guard tolerance > 0, width > 0, height > 0 else { return self }
        let key = color(x: 0, y: 0)
        var copy = self
        let tol = tolerance
        for i in stride(from: 0, to: copy.pixels.count, by: 4) {
            let dr = abs(Int(copy.pixels[i]) - Int(key.r))
            let dg = abs(Int(copy.pixels[i + 1]) - Int(key.g))
            let db = abs(Int(copy.pixels[i + 2]) - Int(key.b))
            if dr <= tol && dg <= tol && db <= tol {
                copy.pixels[i] = 0
                copy.pixels[i + 1] = 0
                copy.pixels[i + 2] = 0
                copy.pixels[i + 3] = 0
            }
        }
        return copy
    }

    public func scaled(to newWidth: Int, newHeight: Int) -> PixelImage {
        let nw = max(1, newWidth)
        let nh = max(1, newHeight)
        if nw == width && nh == height { return self }
        var out = PixelImage(width: nw, height: nh)
        for y in 0..<nh {
            let sy = min(height - 1, Int(Float(y) * Float(height) / Float(nh)))
            for x in 0..<nw {
                let sx = min(width - 1, Int(Float(x) * Float(width) / Float(nw)))
                out.set(x: x, y: y, color(x: sx, y: sy))
            }
        }
        return out
    }

    public func scaled(by factor: Int) -> PixelImage {
        let f = max(1, factor)
        if f == 1 { return self }
        var out = PixelImage(width: width * f, height: height * f)
        for y in 0..<height {
            for x in 0..<width {
                let c = color(x: x, y: y)
                out.fill(x: x * f, y: y * f, w: f, h: f, c)
            }
        }
        return out
    }

    public func opaqueBounds() -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width where color(x: x, y: y).isOpaque {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return (minX, minY, maxX, maxY)
    }

    public mutating func blit(_ other: PixelImage, atX ox: Int, y oy: Int) {
        for y in 0..<other.height {
            for x in 0..<other.width {
                let c = other.color(x: x, y: y)
                if c.a > 0 {
                    set(x: ox + x, y: oy + y, c)
                }
            }
        }
    }

    /// Fills single-pixel gaps that appear when a rotated grid lands between pixels.
    public func sealingPinholes() -> PixelImage {
        var out = self
        for y in 0..<height {
            for x in 0..<width where !color(x: x, y: y).isOpaque {
                let neighbors = [
                    color(x: x - 1, y: y),
                    color(x: x + 1, y: y),
                    color(x: x, y: y - 1),
                    color(x: x, y: y + 1),
                ]
                guard neighbors.allSatisfy(\.isOpaque) else { continue }
                let count = Float(neighbors.count)
                out.set(
                    x: x,
                    y: y,
                    RGBA(
                        r: UInt8(neighbors.reduce(0) { $0 + Int($1.r) } / Int(count)),
                        g: UInt8(neighbors.reduce(0) { $0 + Int($1.g) } / Int(count)),
                        b: UInt8(neighbors.reduce(0) { $0 + Int($1.b) } / Int(count))
                    )
                )
            }
        }
        return out
    }

    /// One-pixel outward stroke so the sprite reads on any backdrop.
    public func outlined(color: RGBA = RGBA(r: 16, g: 14, b: 24)) -> PixelImage {
        var out = self
        let w = width
        let h = height
        func opaque(_ x: Int, _ y: Int) -> Bool {
            contains(x, y) && self.color(x: x, y: y).isOpaque
        }
        for y in 0..<h {
            for x in 0..<w where !self.color(x: x, y: y).isOpaque {
                if opaque(x - 1, y) || opaque(x + 1, y) || opaque(x, y - 1) || opaque(x, y + 1) {
                    out.set(x: x, y: y, color)
                }
            }
        }
        return out
    }

    public func cgImage() -> CGImage? {
        let prem = premultipliedPixels()
        guard let provider = CGDataProvider(data: Data(prem) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private func premultipliedPixels() -> [UInt8] {
        var out = pixels
        for i in stride(from: 0, to: out.count, by: 4) {
            let a = UInt16(out[i + 3])
            if a == 255 || a == 0 { continue }
            out[i] = UInt8(UInt16(out[i]) * a / 255)
            out[i + 1] = UInt8(UInt16(out[i + 1]) * a / 255)
            out[i + 2] = UInt8(UInt16(out[i + 2]) * a / 255)
        }
        return out
    }
}
