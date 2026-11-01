import Foundation

public enum SpriteSheet {
    public static func pack(_ frames: [PixelImage], columns: Int, gap: Int) -> PixelImage {
        guard let first = frames.first else {
            return PixelImage(width: 1, height: 1)
        }
        let cols = max(1, min(columns, frames.count))
        let rows = Int(ceil(Double(frames.count) / Double(cols)))
        let spacing = max(0, gap)
        let width = cols * first.width + max(0, cols - 1) * spacing
        let height = rows * first.height + max(0, rows - 1) * spacing
        var sheet = PixelImage(width: max(1, width), height: max(1, height))
        for (index, frame) in frames.enumerated() {
            let column = index % cols
            let row = index / cols
            let x = column * (first.width + spacing)
            let y = row * (first.height + spacing)
            sheet.blit(frame, atX: x, y: y)
        }
        return sheet
    }

    public static func rows(frameCount: Int, columns: Int) -> Int {
        let cols = max(1, min(columns, max(frameCount, 1)))
        return Int(ceil(Double(max(frameCount, 1)) / Double(cols)))
    }
}

public struct SheetManifest: Codable, Sendable {
    public var generator: String
    public var frameCount: Int
    public var frameWidth: Int
    public var frameHeight: Int
    public var columns: Int
    public var rows: Int
    public var gap: Int
    public var pixelScale: Int
    public var cameraPitchDegrees: Float
    public var pivotX: Int
    public var pivotY: Int
    public var image: String
    public var frames: [FrameRect]

    public struct FrameRect: Codable, Sendable {
        public var index: Int
        public var angleDegrees: Float
        public var x: Int
        public var y: Int
        public var width: Int
        public var height: Int
    }
}

public enum ManifestWriter {
    public static func make(
        frameCount: Int,
        frameWidth: Int,
        frameHeight: Int,
        columns: Int,
        gap: Int,
        pixelScale: Int,
        pitchDegrees: Float,
        pivotX: Int,
        pivotY: Int,
        angles: [Float],
        imageName: String
    ) -> SheetManifest {
        let cols = max(1, min(columns, max(frameCount, 1)))
        let spacing = max(0, gap)
        var frames: [SheetManifest.FrameRect] = []
        for index in 0..<frameCount {
            let column = index % cols
            let row = index / cols
            frames.append(
                SheetManifest.FrameRect(
                    index: index,
                    angleDegrees: index < angles.count ? angles[index] : 0,
                    x: column * (frameWidth + spacing),
                    y: row * (frameHeight + spacing),
                    width: frameWidth,
                    height: frameHeight
                )
            )
        }
        return SheetManifest(
            generator: "Pixel Rotator",
            frameCount: frameCount,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            columns: cols,
            rows: SpriteSheet.rows(frameCount: frameCount, columns: cols),
            gap: spacing,
            pixelScale: pixelScale,
            cameraPitchDegrees: pitchDegrees,
            pivotX: pivotX,
            pivotY: pivotY,
            image: imageName,
            frames: frames
        )
    }
}
