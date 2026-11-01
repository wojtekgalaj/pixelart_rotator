import Foundation
import simd

public struct Exposure: OptionSet, Sendable {
    public var rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let posX = Exposure(rawValue: 1 << 0)
    public static let negX = Exposure(rawValue: 1 << 1)
    public static let posY = Exposure(rawValue: 1 << 2)
    public static let negY = Exposure(rawValue: 1 << 3)
    public static let posZ = Exposure(rawValue: 1 << 4)
    public static let negZ = Exposure(rawValue: 1 << 5)

    public var isEmpty: Bool { rawValue == 0 }
}

public struct Voxel: Sendable {
    public var x: UInt16
    public var y: UInt16
    public var z: UInt16
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8
    public var exposure: Exposure

    public init(
        x: Int,
        y: Int,
        z: Int,
        color: RGBA,
        exposure: Exposure
    ) {
        self.x = UInt16(x)
        self.y = UInt16(y)
        self.z = UInt16(z)
        self.r = color.r
        self.g = color.g
        self.b = color.b
        self.a = color.a
        self.exposure = exposure
    }

    public var color: RGBA { RGBA(r: r, g: g, b: b, a: a) }
}

public struct VoxelModel: Sendable {
    public var width: Int
    public var height: Int
    public var depth: Int
    public var voxels: [Voxel]

    public init(width: Int, height: Int, depth: Int, voxels: [Voxel]) {
        self.width = width
        self.height = height
        self.depth = depth
        self.voxels = voxels
    }

    public var isEmpty: Bool { voxels.isEmpty }

    public var center: SIMD3<Float> {
        SIMD3(Float(width) / 2, Float(height) / 2, Float(depth) / 2)
    }
}

/// Solid grid used while sculpting and carving. Empty cells have alpha 0.
public struct DenseGrid: Sendable {
    public var width: Int
    public var height: Int
    public var depth: Int
    var pixels: [UInt8]

    public init(width: Int, height: Int, depth: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.depth = max(1, depth)
        self.pixels = [UInt8](repeating: 0, count: self.width * self.height * self.depth * 4)
    }

    func offset(_ x: Int, _ y: Int, _ z: Int) -> Int {
        ((z * height + y) * width + x) * 4
    }

    func inBounds(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        x >= 0 && y >= 0 && z >= 0 && x < width && y < height && z < depth
    }

    func isSolid(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        guard inBounds(x, y, z) else { return false }
        return pixels[offset(x, y, z) + 3] >= 16
    }

    func color(_ x: Int, _ y: Int, _ z: Int) -> RGBA {
        guard inBounds(x, y, z) else { return .clear }
        let i = offset(x, y, z)
        return RGBA(r: pixels[i], g: pixels[i + 1], b: pixels[i + 2], a: pixels[i + 3])
    }

    public mutating func set(_ x: Int, _ y: Int, _ z: Int, _ color: RGBA) {
        guard inBounds(x, y, z) else { return }
        let i = offset(x, y, z)
        pixels[i] = color.r
        pixels[i + 1] = color.g
        pixels[i + 2] = color.b
        pixels[i + 3] = color.a
    }

    mutating func fill(x: Range<Int>, y: Range<Int>, z: Range<Int>, _ color: RGBA) {
        for zz in z {
            for yy in y {
                for xx in x {
                    set(xx, yy, zz, color)
                }
            }
        }
    }

    mutating func removeWhere(_ predicate: (Int, Int, Int) -> Bool) {
        for z in 0..<depth {
            for y in 0..<height {
                for x in 0..<width where isSolid(x, y, z) && predicate(x, y, z) {
                    set(x, y, z, .clear)
                }
            }
        }
    }

    var solidCount: Int {
        var n = 0
        for i in stride(from: 3, to: pixels.count, by: 4) where pixels[i] >= 16 {
            n += 1
        }
        return n
    }

    func exposure(at x: Int, y: Int, z: Int) -> Exposure {
        var mask = Exposure()
        if !isSolid(x + 1, y, z) { mask.insert(.posX) }
        if !isSolid(x - 1, y, z) { mask.insert(.negX) }
        if !isSolid(x, y + 1, z) { mask.insert(.posY) }
        if !isSolid(x, y - 1, z) { mask.insert(.negY) }
        if !isSolid(x, y, z + 1) { mask.insert(.posZ) }
        if !isSolid(x, y, z - 1) { mask.insert(.negZ) }
        return mask
    }

    /// Surface voxels only. Fully buried cells can never show up in a picture.
    public func surfaceModel() -> VoxelModel {
        var voxels: [Voxel] = []
        voxels.reserveCapacity(solidCount / 2)
        for z in 0..<depth {
            for y in 0..<height {
                for x in 0..<width where isSolid(x, y, z) {
                    let face = exposure(at: x, y: y, z: z)
                    if face.isEmpty { continue }
                    voxels.append(Voxel(x: x, y: y, z: z, color: color(x, y, z), exposure: face))
                }
            }
        }
        return VoxelModel(width: width, height: height, depth: depth, voxels: voxels)
    }
}
