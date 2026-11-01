import Foundation

public enum AxisRender {
    public static func render(_ model: VoxelModel, _ face: OrthoFace) -> PixelImage {
        let size = ViewMap.imageSize(face, width: model.width, height: model.height, depth: model.depth)
        var image = PixelImage(width: size.0, height: size.1)
        var depths = [Int](repeating: Int.min, count: size.0 * size.1)
        for voxel in model.voxels where voxel.a >= 16 {
            let x = Int(voxel.x)
            let y = Int(voxel.y)
            let z = Int(voxel.z)
            let pix = ViewMap.pixel(
                face,
                x: x, y: y, z: z,
                width: model.width, height: model.height, depth: model.depth
            )
            let d = ViewMap.depth(face, x: x, y: y, z: z)
            let i = pix.y * size.0 + pix.x
            if d >= depths[i] {
                depths[i] = d
                image.set(x: pix.x, y: pix.y, voxel.color)
            }
        }
        return image
    }
}
