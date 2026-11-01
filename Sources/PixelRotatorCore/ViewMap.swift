import Foundation

/// Flat drawings of one object. Transparent pixels are empty space.
public enum OrthoFace: String, CaseIterable, Sendable, Codable, Identifiable {
    case front, back, left, right, top, bottom

    public var id: String { rawValue }

    public static let gallery: [OrthoFace] = [.front, .back, .left, .right, .top, .bottom]

    public var title: String {
        switch self {
        case .front: "Front"
        case .back: "Back"
        case .left: "Left"
        case .right: "Right"
        case .top: "Top"
        case .bottom: "Bottom"
        }
    }

    public var hint: String {
        switch self {
        case .front: "Matches frame 0"
        case .back: "Looking at the rear"
        case .left: "Nose points right"
        case .right: "Nose points left"
        case .top: "Nose points up"
        case .bottom: "Underside, nose up"
        }
    }
}

/// Shared pixel mapping so a drawing, the carved model, and a cardinal camera all agree.
///
/// Object axes: +X is the right side of the front drawing, +Y is up, +Z is the nose.
enum ViewMap {
    static func imageSize(_ face: OrthoFace, width: Int, height: Int, depth: Int) -> (Int, Int) {
        switch face {
        case .front, .back: (width, height)
        case .left, .right: (depth, height)
        case .top, .bottom: (width, depth)
        }
    }

    /// Image pixel for a voxel. Image Y grows downward.
    static func pixel(
        _ face: OrthoFace,
        x: Int,
        y: Int,
        z: Int,
        width: Int,
        height: Int,
        depth: Int
    ) -> (x: Int, y: Int) {
        switch face {
        case .front:
            return (x, height - 1 - y)
        case .back:
            return (width - 1 - x, height - 1 - y)
        case .right:
            // Standing on the object's right, the nose is on the viewer's left.
            return (depth - 1 - z, height - 1 - y)
        case .left:
            return (z, height - 1 - y)
        case .top:
            // Above the object, nose toward the top of the drawing.
            return (x, depth - 1 - z)
        case .bottom:
            return (width - 1 - x, depth - 1 - z)
        }
    }

    /// Larger values are closer to that face's camera.
    static func depth(_ face: OrthoFace, x: Int, y: Int, z: Int) -> Int {
        switch face {
        case .front: z
        case .back: -z
        case .right: x
        case .left: -x
        case .top: y
        case .bottom: -y
        }
    }
}
