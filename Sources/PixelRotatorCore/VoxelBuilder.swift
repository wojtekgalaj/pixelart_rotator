import Foundation

public struct VoxelBuild: Sendable {
    public var model: VoxelModel
    public var width: Int
    public var height: Int
    public var depth: Int
    public var solidCount: Int
    public var resampled: Bool
    public var note: String
}

public enum VoxelBuilder {
    public static func build(
        views: [OrthoFace: PixelImage],
        mirrorSides: Bool,
        thickness: Int,
        maxAxis: Int
    ) -> VoxelBuild {
        var images = views
        if mirrorSides {
            if images[.right] == nil, let left = images[.left] {
                images[.right] = left.flippedHorizontally()
            }
            if images[.left] == nil, let right = images[.right] {
                images[.left] = right.flippedHorizontally()
            }
        }

        let resolved = resolveSize(images: images, thickness: max(1, thickness), maxAxis: max(8, maxAxis))
        var scaled: [OrthoFace: PixelImage] = [:]
        var resampled = false
        for (face, image) in images {
            let size = ViewMap.imageSize(face, width: resolved.width, height: resolved.height, depth: resolved.depth)
            if image.width != size.0 || image.height != size.1 {
                resampled = true
            }
            scaled[face] = image.scaled(to: size.0, newHeight: size.1)
        }

        var grid = DenseGrid(width: resolved.width, height: resolved.height, depth: resolved.depth)
        // Start solid, then let every supplied drawing cut away its transparent pixels.
        let solid = RGBA(r: 128, g: 128, b: 128, a: 255)
        for z in 0..<grid.depth {
            for y in 0..<grid.height {
                for x in 0..<grid.width {
                    grid.set(x, y, z, solid)
                }
            }
        }

        for (face, image) in scaled {
            let width = grid.width
            let height = grid.height
            let depth = grid.depth
            grid.removeWhere { x, y, z in
                let pix = ViewMap.pixel(
                    face, x: x, y: y, z: z,
                    width: width, height: height, depth: depth
                )
                return !image.color(x: pix.x, y: pix.y).isOpaque
            }
        }

        colorSurfaces(&grid, views: scaled)
        let model = grid.surfaceModel()
        let note = "\(grid.width)×\(grid.height)×\(grid.depth) voxels · \(grid.solidCount) solid"
        return VoxelBuild(
            model: model,
            width: grid.width,
            height: grid.height,
            depth: grid.depth,
            solidCount: grid.solidCount,
            resampled: resampled,
            note: note
        )
    }

    private static func resolveSize(
        images: [OrthoFace: PixelImage],
        thickness: Int,
        maxAxis: Int
    ) -> (width: Int, height: Int, depth: Int) {
        var width = 0
        var height = 0
        var depth = 0
        for (face, image) in images {
            switch face {
            case .front, .back:
                width = max(width, image.width)
                height = max(height, image.height)
            case .left, .right:
                depth = max(depth, image.width)
                height = max(height, image.height)
            case .top, .bottom:
                width = max(width, image.width)
                depth = max(depth, image.height)
            }
        }
        if width == 0 { width = thickness }
        if height == 0 { height = thickness }
        if depth == 0 { depth = thickness }
        let longest = max(width, max(height, depth))
        if longest > maxAxis {
            let scale = Float(maxAxis) / Float(longest)
            width = max(1, Int((Float(width) * scale).rounded()))
            height = max(1, Int((Float(height) * scale).rounded()))
            depth = max(1, Int((Float(depth) * scale).rounded()))
        }
        return (width, height, depth)
    }

    private static func colorSurfaces(_ grid: inout DenseGrid, views: [OrthoFace: PixelImage]) {
        for z in 0..<grid.depth {
            for y in 0..<grid.height {
                for x in 0..<grid.width where grid.isSolid(x, y, z) {
                    let exposure = grid.exposure(at: x, y: y, z: z)
                    if exposure.isEmpty { continue }
                    let color = surfaceColor(x: x, y: y, z: z, exposure: exposure, grid: grid, views: views)
                    grid.set(x, y, z, color)
                }
            }
        }
    }

    private static func surfaceColor(
        x: Int,
        y: Int,
        z: Int,
        exposure: Exposure,
        grid: DenseGrid,
        views: [OrthoFace: PixelImage]
    ) -> RGBA {
        var red: Float = 0
        var green: Float = 0
        var blue: Float = 0
        var weight: Float = 0

        func add(_ face: OrthoFace, _ amount: Float) {
            guard amount > 0, let image = views[face] else { return }
            let pix = ViewMap.pixel(
                face, x: x, y: y, z: z,
                width: grid.width, height: grid.height, depth: grid.depth
            )
            let sample = image.color(x: pix.x, y: pix.y)
            guard sample.isOpaque else { return }
            red += Float(sample.r) * amount
            green += Float(sample.g) * amount
            blue += Float(sample.b) * amount
            weight += amount
        }

        if exposure.contains(.posZ) { add(.front, 1) }
        if exposure.contains(.negZ) { add(.back, 1) }
        if exposure.contains(.posX) { add(.right, 1) }
        if exposure.contains(.negX) { add(.left, 1) }
        if exposure.contains(.posY) { add(.top, 1) }
        if exposure.contains(.negY) { add(.bottom, 1) }

        if weight == 0 {
            add(.front, 1)
            add(.back, 1)
            add(.right, 1)
            add(.left, 1)
            add(.top, 1)
            add(.bottom, 1)
        }

        guard weight > 0 else {
            return RGBA(r: 140, g: 140, b: 148)
        }
        return RGBA(
            r: UInt8(min(255, red / weight)),
            g: UInt8(min(255, green / weight)),
            b: UInt8(min(255, blue / weight))
        )
    }
}
