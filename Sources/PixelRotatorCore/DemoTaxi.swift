import Foundation

public enum DemoTaxi {
    public static func blueprints() -> [OrthoFace: PixelImage] {
        let model = sculpt()
        var views: [OrthoFace: PixelImage] = [:]
        for face in OrthoFace.allCases {
            views[face] = AxisRender.render(model, face)
        }
        return views
    }

    public static func sculpt() -> VoxelModel {
        let navy = RGBA(r: 24, g: 42, b: 84)
        let ink = RGBA(r: 12, g: 20, b: 44)
        let roof = RGBA(r: 18, g: 28, b: 58)
        let glass = RGBA(r: 166, g: 226, b: 255)
        let glassDeep = RGBA(r: 36, g: 78, b: 128)
        let yellow = RGBA(r: 255, g: 204, b: 32)
        let cyan = RGBA(r: 54, g: 246, b: 255)
        let magenta = RGBA(r: 255, g: 48, b: 128)
        let white = RGBA(r: 246, g: 252, b: 255)
        let tire = RGBA(r: 16, g: 16, b: 20)
        let bumper = RGBA(r: 186, g: 198, b: 210)
        let under = RGBA(r: 8, g: 10, b: 18)

        var grid = DenseGrid(width: 23, height: 20, depth: 44)

        // Wheels sit outside the body so the stance reads from the front.
        let wheels = [(0, 6), (19, 6), (0, 31), (19, 31)]
        for (x, z) in wheels {
            grid.fill(x: x..<(x + 4), y: 0..<5, z: z..<(z + 6), tire)
        }
        // Hubs on the outer faces.
        for z in [8, 33] {
            grid.set(0, 2, z, cyan)
            grid.set(0, 2, z + 1, cyan)
            grid.set(22, 2, z, cyan)
            grid.set(22, 2, z + 1, cyan)
        }

        grid.fill(x: 4..<19, y: 4..<9, z: 3..<41, navy)
        grid.fill(x: 4..<19, y: 4..<5, z: 3..<41, under)
        grid.fill(x: 5..<18, y: 9..<15, z: 14..<31, ink)
        grid.fill(x: 5..<18, y: 14..<15, z: 14..<31, roof)

        // Hood and trunk stay low; the cabin sits in the middle.
        grid.fill(x: 4..<19, y: 7..<9, z: 31..<41, navy)
        grid.fill(x: 4..<19, y: 7..<9, z: 3..<14, navy)

        grid.fill(x: 3..<20, y: 4..<7, z: 40..<44, bumper)
        grid.fill(x: 3..<20, y: 4..<7, z: 0..<3, bumper)

        // Taxi sign.
        grid.fill(x: 8..<15, y: 15..<19, z: 18..<27, cyan)
        grid.fill(x: 9..<14, y: 15..<18, z: 19..<26, yellow)

        // Glass.
        grid.fill(x: 6..<17, y: 10..<14, z: 30..<31, glass)
        grid.fill(x: 6..<17, y: 10..<13, z: 14..<15, glassDeep)
        grid.fill(x: 5..<6, y: 10..<14, z: 16..<29, glass)
        grid.fill(x: 17..<18, y: 10..<14, z: 16..<29, glass)
        grid.fill(x: 7..<16, y: 14..<15, z: 17..<28, glassDeep)

        // Yellow belt and cyan underglow.
        grid.fill(x: 4..<5, y: 6..<8, z: 6..<40, yellow)
        grid.fill(x: 18..<19, y: 6..<8, z: 6..<40, yellow)
        grid.fill(x: 4..<19, y: 6..<8, z: 40..<41, yellow)
        grid.fill(x: 4..<5, y: 4..<5, z: 8..<38, cyan)
        grid.fill(x: 18..<19, y: 4..<5, z: 8..<38, cyan)

        // Lights.
        grid.fill(x: 4..<8, y: 5..<7, z: 43..<44, white)
        grid.fill(x: 15..<19, y: 5..<7, z: 43..<44, white)
        grid.fill(x: 8..<15, y: 4..<6, z: 43..<44, ink)
        grid.fill(x: 4..<8, y: 5..<7, z: 0..<1, magenta)
        grid.fill(x: 15..<19, y: 5..<7, z: 0..<1, magenta)

        // A stripe on the hood so the nose stays readable when the car turns.
        grid.fill(x: 10..<13, y: 8..<9, z: 34..<41, cyan)

        return grid.surfaceModel()
    }
}
