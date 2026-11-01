import Foundation
import PixelRotatorCore

@main
struct PixelRotatorCheck {
    static func main() {
        do {
            try run()
        } catch {
            fputs("FAIL \(error)\n", stderr)
            exit(1)
        }
    }

    static func run() throws {
        try roundTripPNG()
        try frontCamera()
        try rightCamera()
        try topCamera()
        try frontRebuild()
        try transparencyCuts()
        try sheetPack()
        try holdNearest()
        try demo()
        print("OK")
    }

    static func roundTripPNG() throws {
        var image = PixelImage(width: 2, height: 2)
        image.set(x: 0, y: 0, RGBA(r: 255, g: 0, b: 0))
        image.set(x: 1, y: 1, RGBA(r: 0, g: 0, b: 255))
        let back = try ImageCoding.decode(ImageCoding.pngData(image))
        expect(back.color(x: 0, y: 0) == RGBA(r: 255, g: 0, b: 0), "png top-left \(back.color(x: 0, y: 0))")
        expect(back.color(x: 1, y: 1) == RGBA(r: 0, g: 0, b: 255), "png bottom-right \(back.color(x: 1, y: 1))")
    }

    static func frontCamera() {
        let model = painted(width: 5, height: 4, depth: 3, face: .front)
        let drawing = AxisRender.render(model, .front)
        let photo = Turntable.renderTight(model: model, yaw: 0, pitch: 0)
        expectSame(photo, drawing, "front camera")
    }

    static func rightCamera() {
        let model = painted(width: 4, height: 3, depth: 6, face: .right)
        let drawing = AxisRender.render(model, .right)
        let photo = Turntable.renderTight(model: model, yaw: .pi / 2, pitch: 0)
        expectSame(photo, drawing, "right camera")
    }

    static func topCamera() {
        let model = painted(width: 5, height: 4, depth: 7, face: .top)
        let drawing = AxisRender.render(model, .top)
        let photo = Turntable.renderTight(model: model, yaw: 0, pitch: .pi / 2)
        expectSame(photo, drawing, "top camera")
    }

    static func frontRebuild() {
        var source = PixelImage(width: 4, height: 3)
        for y in 0..<3 {
            for x in 0..<4 {
                source.set(x: x, y: y, RGBA(r: UInt8(40 + x * 20), g: UInt8(30 + y * 40), b: 180))
            }
        }
        source.set(x: 0, y: 0, .clear)
        let build = VoxelBuilder.build(views: [.front: source], mirrorSides: false, thickness: 1, maxAxis: 64)
        expect(build.width == 4 && build.height == 3 && build.depth == 1, "front size \(build.width) \(build.height) \(build.depth)")
        expectSame(AxisRender.render(build.model, .front), source, "front rebuild")
    }

    static func transparencyCuts() {
        var front = PixelImage(width: 3, height: 3, fill: RGBA(r: 200, g: 40, b: 40))
        front.set(x: 1, y: 1, .clear)
        let side = PixelImage(width: 4, height: 3, fill: RGBA(r: 40, g: 40, b: 200))
        let build = VoxelBuilder.build(
            views: [.front: front, .right: side],
            mirrorSides: false,
            thickness: 4,
            maxAxis: 32
        )
        expect(!build.model.voxels.contains { Int($0.x) == 1 && Int($0.y) == 1 }, "center column remains")
        expect(build.model.voxels.contains { Int($0.x) == 0 && Int($0.z) == 3 }, "corner voxel missing")
    }

    static func sheetPack() {
        let frames = (0..<4).map { index in
            PixelImage(width: 2, height: 2, fill: RGBA(r: UInt8(index * 40), g: 0, b: 0))
        }
        let sheet = SpriteSheet.pack(frames, columns: 2, gap: 1)
        expect(sheet.width == 5 && sheet.height == 5, "sheet size")
        expect(sheet.color(x: 0, y: 0).r == 0, "frame 0")
        expect(sheet.color(x: 3, y: 0).r == 40, "frame 1")
        expect(sheet.color(x: 0, y: 3).r == 80, "frame 2")
        expect(sheet.color(x: 2, y: 0).a == 0, "gap")
    }

    static func holdNearest() {
        let result = SpriteFactory.spinDrawings(
            drawings: [
                AngleDrawing(angleDegrees: 0, image: PixelImage(width: 2, height: 2, fill: RGBA(r: 255, g: 0, b: 0))),
                AngleDrawing(angleDegrees: 90, image: PixelImage(width: 2, height: 2, fill: RGBA(r: 0, g: 0, b: 255))),
            ],
            steps: 4,
            mirrorOtherSide: false,
            inbetween: .hold,
            outline: false,
            pixelScale: 1,
            columns: 4,
            gap: 0
        )
        expect(result.frames.count == 4, "hold count")
        expect(result.frames[0].color(x: 1, y: 1).r == 255, "hold frame 0")
        expect(result.frames[1].color(x: 1, y: 1).b == 255, "hold frame 1")
    }

    static func demo() throws {
        let clock = ContinuousClock()
        let start = clock.now
        let views = DemoTaxi.blueprints()
        expect(views.count == 6, "demo views")
        let result = SpriteFactory.spinBlueprints(
            views: views,
            mirrorSides: true,
            thickness: 8,
            maxAxis: 128,
            steps: 16,
            pitchDegrees: 34,
            shading: true,
            outline: true,
            pixelScale: 2,
            columns: 8,
            gap: 0
        )
        let elapsed = clock.now - start
        expect(result.frames.count == 16, "demo frames")
        expect(result.sheet.width > result.frames[0].width, "sheet wider than a frame")
        let folder = URL(fileURLWithPath: "/tmp/pixel-rotator", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ImageCoding.writePNG(result.sheet, to: folder.appendingPathComponent("sheet.png"))
        try ImageCoding.writePNG(result.frames[0], to: folder.appendingPathComponent("frame0.png"))
        try ImageCoding.writePNG(result.frames[4], to: folder.appendingPathComponent("frame4.png"))
        try ImageCoding.writePNG(result.frames[8], to: folder.appendingPathComponent("frame8.png"))
        try ImageCoding.writePNG(views[.front]!, to: folder.appendingPathComponent("view-front.png"))
        try ImageCoding.writePNG(views[.right]!, to: folder.appendingPathComponent("view-right.png"))
        try ImageCoding.writePNG(views[.top]!, to: folder.appendingPathComponent("view-top.png"))
        try ImageCoding.writePNG(views[.back]!, to: folder.appendingPathComponent("view-back.png"))
        let reference = Turntable.render(
            model: DemoTaxi.sculpt(),
            steps: 8,
            pitchDegrees: 34,
            shading: true,
            outline: false,
            stabilized: true
        )
        try ImageCoding.writePNG(reference.frames[1].image.scaled(by: 3), to: folder.appendingPathComponent("sculpt.png"))
        try ImageCoding.writeGIF(result.frames, fps: 10, to: folder.appendingPathComponent("spin.gif"))
        print("demo \(elapsed) · \(result.summary)")
    }

    static func painted(width: Int, height: Int, depth: Int, face: OrthoFace) -> VoxelModel {
        var grid = DenseGrid(width: width, height: height, depth: depth)
        switch face {
        case .front:
            for y in 0..<height {
                for x in 0..<width {
                    grid.set(x, y, depth - 1, RGBA(r: UInt8(20 + x * 30), g: UInt8(15 + y * 35), b: 220))
                }
            }
        case .right:
            for y in 0..<height {
                for z in 0..<depth {
                    grid.set(width - 1, y, z, RGBA(r: UInt8(30 + z * 12), g: 180, b: UInt8(20 + y * 30)))
                }
            }
        case .top:
            for z in 0..<depth {
                for x in 0..<width {
                    grid.set(x, height - 1, z, RGBA(r: UInt8(40 + x * 20), g: UInt8(min(255, 200 - z * 8)), b: 90))
                }
            }
        default:
            break
        }
        return grid.surfaceModel()
    }

    static func expectSame(_ a: PixelImage, _ b: PixelImage, _ name: String) {
        if a.width != b.width || a.height != b.height || a.pixels != b.pixels {
            fputs(
                "FAIL \(name): \(a.width)x\(a.height) vs \(b.width)x\(b.height)\n",
                stderr
            )
            exit(1)
        }
    }

    static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            fputs("FAIL \(message)\n", stderr)
            exit(1)
        }
    }
}
