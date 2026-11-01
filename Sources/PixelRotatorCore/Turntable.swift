import Foundation
import simd

public struct ProjectedPoint: Sendable {
    public var x: Float
    public var y: Float
    public var depth: Float
}

/// Object yaw spins around up. Camera pitch lifts the view: 0 is side-on, 90 is straight down.
public enum Projector {
    public static func project(
        _ point: SIMD3<Float>,
        yaw: Float,
        pitch: Float,
        center: SIMD3<Float>
    ) -> ProjectedPoint {
        let r = point - center
        let cy = cos(yaw)
        let sy = sin(yaw)
        let x1 = r.x * cy - r.z * sy
        let z1 = r.x * sy + r.z * cy
        let y1 = r.y
        let cp = cos(pitch)
        let sp = sin(pitch)
        return ProjectedPoint(
            x: x1,
            y: y1 * cp + z1 * sp,
            depth: y1 * sp + z1 * cp
        )
    }
}

public struct TurntableFrame: Sendable, Equatable {
    public var image: PixelImage
    public var angleDegrees: Float
}

public struct TurntableResult: Sendable {
    public var frames: [TurntableFrame]
    public var pivotX: Int
    public var pivotY: Int
}

public enum Turntable {
    struct Viewport {
        var minX: Float
        var maxX: Float
        var minY: Float
        var maxY: Float
        var width: Int
        var height: Int
        var pad: Int
    }

    public static func render(
        model: VoxelModel,
        steps: Int,
        pitchDegrees: Float,
        shading: Bool,
        outline: Bool,
        stabilized: Bool
    ) -> TurntableResult {
        let count = max(1, steps)
        let pitch = pitchDegrees * .pi / 180
        let pad = outline ? 2 : 1
        let yaws = (0..<count).map { Float($0) / Float(count) * Float.pi * 2 }
        let viewport = makeViewport(model: model, yaws: stabilized ? yaws : [yaws[0]], pitch: pitch, pad: pad)
        let light = simd_normalize(SIMD3<Float>(-0.32, 0.78, 0.54))
        var frames: [TurntableFrame] = []
        frames.reserveCapacity(count)
        for (index, yaw) in yaws.enumerated() {
            let frameViewport: Viewport
            if stabilized {
                frameViewport = viewport
            } else {
                frameViewport = makeViewport(model: model, yaws: [yaw], pitch: pitch, pad: pad)
            }
            var image = rasterize(
                model: model,
                yaw: yaw,
                pitch: pitch,
                viewport: frameViewport,
                light: light,
                shading: shading
            )
            image = image.sealingPinholes()
            if outline {
                image = image.outlined()
            }
            let degrees = Float(index) / Float(count) * 360
            frames.append(TurntableFrame(image: image, angleDegrees: degrees))
        }
        let pivot = projectPivot(model: model, pitch: pitch, viewport: viewport)
        return TurntableResult(frames: frames, pivotX: pivot.x, pivotY: pivot.y)
    }

    public static func renderTight(
        model: VoxelModel,
        yaw: Float,
        pitch: Float,
        shading: Bool = false
    ) -> PixelImage {
        let viewport = makeViewport(model: model, yaws: [yaw], pitch: pitch, pad: 0)
        return rasterize(
            model: model,
            yaw: yaw,
            pitch: pitch,
            viewport: viewport,
            light: simd_normalize(SIMD3<Float>(0, 1, 0)),
            shading: shading
        )
    }

    private static func makeViewport(model: VoxelModel, yaws: [Float], pitch: Float, pad: Int) -> Viewport {
        let center = model.center
        var minX = Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude
        let xs: [Float] = [0, Float(model.width)]
        let ys: [Float] = [0, Float(model.height)]
        let zs: [Float] = [0, Float(model.depth)]
        for yaw in yaws {
            for x in xs {
                for y in ys {
                    for z in zs {
                        let p = Projector.project(SIMD3(x, y, z), yaw: yaw, pitch: pitch, center: center)
                        minX = min(minX, p.x)
                        maxX = max(maxX, p.x)
                        minY = min(minY, p.y)
                        maxY = max(maxY, p.y)
                    }
                }
            }
        }
        if minX > maxX {
            minX = 0
            maxX = 1
            minY = 0
            maxY = 1
        }
        let width = max(1, Int(round(maxX - minX))) + pad * 2
        let height = max(1, Int(round(maxY - minY))) + pad * 2
        return Viewport(minX: minX, maxX: maxX, minY: minY, maxY: maxY, width: width, height: height, pad: pad)
    }

    private static func rasterize(
        model: VoxelModel,
        yaw: Float,
        pitch: Float,
        viewport: Viewport,
        light: SIMD3<Float>,
        shading: Bool
    ) -> PixelImage {
        var image = PixelImage(width: viewport.width, height: viewport.height)
        var zbuffer = [Float](repeating: -.greatestFiniteMagnitude, count: viewport.width * viewport.height)
        let center = model.center
        let cy = cos(yaw)
        let sy = sin(yaw)
        for voxel in model.voxels {
            let point = SIMD3<Float>(Float(voxel.x) + 0.5, Float(voxel.y) + 0.5, Float(voxel.z) + 0.5)
            let projected = Projector.project(point, yaw: yaw, pitch: pitch, center: center)
            let ix = Int(floor(projected.x - viewport.minX)) + viewport.pad
            let iy = Int(floor(viewport.maxY - projected.y)) + viewport.pad
            guard image.contains(ix, iy) else { continue }
            let i = iy * viewport.width + ix
            if projected.depth <= zbuffer[i] { continue }
            zbuffer[i] = projected.depth
            var color = voxel.color
            if shading {
                let shade = shadeAmount(exposure: voxel.exposure, cy: cy, sy: sy, light: light)
                color.r = UInt8(min(255, Float(color.r) * shade))
                color.g = UInt8(min(255, Float(color.g) * shade))
                color.b = UInt8(min(255, Float(color.b) * shade))
            }
            image.set(x: ix, y: iy, color)
        }
        return image
    }

    private static func shadeAmount(
        exposure: Exposure,
        cy: Float,
        sy: Float,
        light: SIMD3<Float>
    ) -> Float {
        // Rotate the light into the object's frame so the highlight travels as it turns.
        let lx = light.x * cy + light.z * sy
        let ly = light.y
        let lz = -light.x * sy + light.z * cy
        let objectLight = SIMD3<Float>(lx, ly, lz)
        var best: Float = 0.58
        let faces: [(Exposure, SIMD3<Float>)] = [
            (.posX, SIMD3(1, 0, 0)),
            (.negX, SIMD3(-1, 0, 0)),
            (.posY, SIMD3(0, 1, 0)),
            (.negY, SIMD3(0, -1, 0)),
            (.posZ, SIMD3(0, 0, 1)),
            (.negZ, SIMD3(0, 0, -1)),
        ]
        for (mask, normal) in faces where exposure.contains(mask) {
            let lambert = max(0, simd_dot(normal, objectLight))
            best = max(best, 0.58 + 0.5 * lambert)
        }
        return min(best, 1.15)
    }

    private static func projectPivot(model: VoxelModel, pitch: Float, viewport: Viewport) -> (x: Int, y: Int) {
        let ground = SIMD3<Float>(Float(model.width) / 2, 0, Float(model.depth) / 2)
        let projected = Projector.project(ground, yaw: 0, pitch: pitch, center: model.center)
        let ix = Int(floor(projected.x - viewport.minX)) + viewport.pad
        let iy = Int(floor(viewport.maxY - projected.y)) + viewport.pad
        return (ix, iy)
    }
}
