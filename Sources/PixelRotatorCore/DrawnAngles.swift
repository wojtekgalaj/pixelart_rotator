import Foundation

public enum Inbetween: String, CaseIterable, Sendable, Codable, Identifiable {
    case hold
    case dither
    case dissolve

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hold: "Hold nearest"
        case .dither: "Pixel dither"
        case .dissolve: "Dissolve"
        }
    }
}

public struct AngleDrawing: Sendable {
    public var angleDegrees: Float
    public var image: PixelImage

    public init(angleDegrees: Float, image: PixelImage) {
        self.angleDegrees = angleDegrees
        self.image = image
    }
}

enum DrawnAngles {
    private static let bayer: [Float] = [
        0, 8, 2, 10,
        12, 4, 14, 6,
        3, 11, 1, 9,
        15, 7, 13, 5,
    ].map { ($0 + 0.5) / 16 }

    static func render(
        drawings: [AngleDrawing],
        steps: Int,
        mirrorOtherSide: Bool,
        inbetween: Inbetween,
        outline: Bool
    ) -> (frames: [PixelImage], angles: [Float], pivotX: Int, pivotY: Int, note: String) {
        var source = drawings.filter { $0.image.opaqueBounds() != nil }
        if mirrorOtherSide {
            source.append(contentsOf: mirrored(source))
        }
        let placed = layout(source)
        guard let canvas = placed.first?.image else {
            return ([], [], 0, 0, "Add at least one drawing.")
        }
        let count = max(1, steps)
        let keys = placed.sorted { normalize($0.angleDegrees) < normalize($1.angleDegrees) }
        var frames: [PixelImage] = []
        var angles: [Float] = []
        frames.reserveCapacity(count)
        for index in 0..<count {
            let angle = Float(index) / Float(count) * 360
            angles.append(angle)
            var frame = frame(at: angle, keys: keys, style: inbetween)
            if outline {
                frame = frame.outlined()
            }
            frames.append(frame)
        }
        let pivotX = canvas.width / 2
        let pivotY = canvas.height - 2
        let mirroredCount = max(0, keys.count - drawings.count)
        let note = "\(drawings.count) drawings"
            + (mirroredCount > 0 ? " · \(mirroredCount) mirrored" : "")
            + " · \(count) frames"
        return (frames, angles, pivotX, pivotY, note)
    }

    private static func mirrored(_ drawings: [AngleDrawing]) -> [AngleDrawing] {
        var extras: [AngleDrawing] = []
        let existing = Set(drawings.map { Int(normalize($0.angleDegrees).rounded()) % 360 })
        for drawing in drawings {
            let angle = normalize(drawing.angleDegrees)
            let rounded = Int(angle.rounded()) % 360
            if rounded == 0 || rounded == 180 { continue }
            let opposite = normalize(360 - angle)
            let slot = Int(opposite.rounded()) % 360
            if existing.contains(slot) { continue }
            extras.append(AngleDrawing(angleDegrees: opposite, image: drawing.image.flippedHorizontally()))
        }
        return extras
    }

    private static func layout(_ drawings: [AngleDrawing]) -> [AngleDrawing] {
        struct Trimmed {
            var angle: Float
            var image: PixelImage
            var minX: Int
            var minY: Int
            var maxX: Int
            var maxY: Int
        }
        var trimmed: [Trimmed] = []
        for drawing in drawings {
            guard let bounds = drawing.image.opaqueBounds() else { continue }
            trimmed.append(Trimmed(
                angle: normalize(drawing.angleDegrees),
                image: drawing.image,
                minX: bounds.minX,
                minY: bounds.minY,
                maxX: bounds.maxX,
                maxY: bounds.maxY
            ))
        }
        guard !trimmed.isEmpty else { return [] }
        let maxWidth = trimmed.map { $0.maxX - $0.minX + 1 }.max() ?? 1
        let maxHeight = trimmed.map { $0.maxY - $0.minY + 1 }.max() ?? 1
        let canvasW = maxWidth + 2
        let canvasH = maxHeight + 2
        return trimmed.map { item in
            let cropW = item.maxX - item.minX + 1
            let cropH = item.maxY - item.minY + 1
            let originX = 1 + (maxWidth - cropW) / 2
            let originY = 1 + (maxHeight - cropH)
            var canvas = PixelImage(width: canvasW, height: canvasH)
            for y in 0..<cropH {
                for x in 0..<cropW {
                    canvas.set(
                        x: originX + x,
                        y: originY + y,
                        item.image.color(x: item.minX + x, y: item.minY + y)
                    )
                }
            }
            return AngleDrawing(angleDegrees: item.angle, image: canvas)
        }
    }

    private static func frame(at angle: Float, keys: [AngleDrawing], style: Inbetween) -> PixelImage {
        if keys.count == 1 { return keys[0].image }
        switch style {
        case .hold:
            return nearest(to: angle, keys: keys).image
        case .dither, .dissolve:
            let pair = segment(containing: angle, keys: keys)
            let start = keys[pair.start]
            let end = keys[pair.end]
            if pair.span < 0.001 || pair.t < 0.001 { return start.image }
            if pair.t > 0.999 { return end.image }
            if style == .dither {
                return dither(start.image, end.image, t: pair.t)
            }
            return dissolve(start.image, end.image, t: pair.t)
        }
    }

    private static func nearest(to angle: Float, keys: [AngleDrawing]) -> AngleDrawing {
        keys.min { angularDistance($0.angleDegrees, angle) < angularDistance($1.angleDegrees, angle) } ?? keys[0]
    }

    private static func segment(containing angle: Float, keys: [AngleDrawing]) -> (start: Int, end: Int, t: Float, span: Float) {
        let theta = normalize(angle)
        for index in keys.indices {
            let next = (index + 1) % keys.count
            let span = clockwiseDistance(from: keys[index].angleDegrees, to: keys[next].angleDegrees)
            let into = clockwiseDistance(from: keys[index].angleDegrees, to: theta)
            if into <= span + 0.001 {
                let t = span < 0.001 ? Float(0) : into / span
                return (index, next, min(1, max(0, t)), span)
            }
        }
        return (0, min(1, keys.count - 1), 0, 0)
    }

    private static func dither(_ a: PixelImage, _ b: PixelImage, t: Float) -> PixelImage {
        var out = PixelImage(width: a.width, height: a.height)
        for y in 0..<a.height {
            for x in 0..<a.width {
                let threshold = bayer[(y % 4) * 4 + (x % 4)]
                out.set(x: x, y: y, t > threshold ? b.color(x: x, y: y) : a.color(x: x, y: y))
            }
        }
        return out
    }

    private static func dissolve(_ a: PixelImage, _ b: PixelImage, t: Float) -> PixelImage {
        var out = PixelImage(width: a.width, height: a.height)
        let t = min(1, max(0, t))
        for y in 0..<a.height {
            for x in 0..<a.width {
                let ca = a.color(x: x, y: y)
                let cb = b.color(x: x, y: y)
                let aa = Float(ca.a) / 255
                let ba = Float(cb.a) / 255
                let outA = (1 - t) * aa + t * ba
                if outA < 1 / 255 {
                    continue
                }
                let wa = (1 - t) * aa
                let wb = t * ba
                out.set(
                    x: x,
                    y: y,
                    RGBA(
                        r: UInt8(min(255, (Float(ca.r) * wa + Float(cb.r) * wb) / outA)),
                        g: UInt8(min(255, (Float(ca.g) * wa + Float(cb.g) * wb) / outA)),
                        b: UInt8(min(255, (Float(ca.b) * wa + Float(cb.b) * wb) / outA)),
                        a: UInt8(min(255, outA * 255))
                    )
                )
            }
        }
        return out
    }

    private static func normalize(_ degrees: Float) -> Float {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value
    }

    private static func clockwiseDistance(from: Float, to: Float) -> Float {
        normalize(to - from)
    }

    private static func angularDistance(_ a: Float, _ b: Float) -> Float {
        let delta = abs(normalize(a - b))
        return min(delta, 360 - delta)
    }
}
