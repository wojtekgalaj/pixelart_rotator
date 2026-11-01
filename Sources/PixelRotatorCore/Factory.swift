import Foundation

public enum SpinSource: String, CaseIterable, Sendable, Identifiable {
    case blueprints
    case drawings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .blueprints: "Flat views"
        case .drawings: "Drawn angles"
        }
    }
}

public struct SpinResult: Sendable {
    public var frames: [PixelImage]
    public var angles: [Float]
    public var sheet: PixelImage
    public var pivotX: Int
    public var pivotY: Int
    public var summary: String
    public var warning: String?
    public var pitchDegrees: Float
    public var pixelScale: Int
    public var columns: Int
    public var gap: Int

    public static let empty = SpinResult(
        frames: [],
        angles: [],
        sheet: PixelImage(width: 1, height: 1),
        pivotX: 0,
        pivotY: 0,
        summary: "Drop in a front, a side, and a top.",
        warning: nil,
        pitchDegrees: 0,
        pixelScale: 1,
        columns: 1,
        gap: 0
    )
}

public enum SpriteFactory {
    public static func spinBlueprints(
        views: [OrthoFace: PixelImage],
        mirrorSides: Bool,
        thickness: Int,
        maxAxis: Int,
        steps: Int,
        pitchDegrees: Float,
        shading: Bool,
        outline: Bool,
        pixelScale: Int,
        columns: Int,
        gap: Int
    ) -> SpinResult {
        let supplied = views.filter { $0.value.opaqueBounds() != nil }
        guard !supplied.isEmpty else {
            var empty = SpinResult.empty
            empty.summary = "Add at least one view. Front, side, and top are the useful set."
            return empty
        }

        let build = VoxelBuilder.build(
            views: supplied,
            mirrorSides: mirrorSides,
            thickness: thickness,
            maxAxis: maxAxis
        )
        guard build.solidCount > 0 else {
            var empty = SpinResult.empty
            empty.warning = "Those views carved the whole object away. Paint windows and lights as solid pixels — transparency is a hole that goes all the way through."
            empty.summary = build.note
            return empty
        }

        let turn = Turntable.render(
            model: build.model,
            steps: steps,
            pitchDegrees: pitchDegrees,
            shading: shading,
            outline: outline,
            stabilized: true
        )
        return finish(
            frames: turn.frames.map(\.image),
            angles: turn.frames.map(\.angleDegrees),
            pivotX: turn.pivotX,
            pivotY: turn.pivotY,
            summary: summary(build: build, frames: steps, pitch: pitchDegrees),
            warning: build.resampled ? "Views were different sizes, so they were snapped onto one voxel grid." : nil,
            pitchDegrees: pitchDegrees,
            pixelScale: pixelScale,
            columns: columns,
            gap: gap
        )
    }

    public static func spinDrawings(
        drawings: [AngleDrawing],
        steps: Int,
        mirrorOtherSide: Bool,
        inbetween: Inbetween,
        outline: Bool,
        pixelScale: Int,
        columns: Int,
        gap: Int
    ) -> SpinResult {
        let rendered = DrawnAngles.render(
            drawings: drawings,
            steps: steps,
            mirrorOtherSide: mirrorOtherSide,
            inbetween: inbetween,
            outline: outline
        )
        guard !rendered.frames.isEmpty else {
            var empty = SpinResult.empty
            empty.summary = "Add drawings and set the angle each one faces."
            return empty
        }
        return finish(
            frames: rendered.frames,
            angles: rendered.angles,
            pivotX: rendered.pivotX,
            pivotY: rendered.pivotY,
            summary: rendered.note,
            warning: nil,
            pitchDegrees: 0,
            pixelScale: pixelScale,
            columns: columns,
            gap: gap
        )
    }

    public static func manifest(for result: SpinResult, imageName: String) -> SheetManifest {
        let frame = result.frames.first
        return ManifestWriter.make(
            frameCount: result.frames.count,
            frameWidth: frame?.width ?? 0,
            frameHeight: frame?.height ?? 0,
            columns: result.columns,
            gap: result.gap,
            pixelScale: result.pixelScale,
            pitchDegrees: result.pitchDegrees,
            pivotX: result.pivotX,
            pivotY: result.pivotY,
            angles: result.angles,
            imageName: imageName
        )
    }

    private static func finish(
        frames: [PixelImage],
        angles: [Float],
        pivotX: Int,
        pivotY: Int,
        summary: String,
        warning: String?,
        pitchDegrees: Float,
        pixelScale: Int,
        columns: Int,
        gap: Int
    ) -> SpinResult {
        let scale = max(1, pixelScale)
        let scaled = frames.map { $0.scaled(by: scale) }
        let cols = max(1, min(columns, max(scaled.count, 1)))
        let sheet = SpriteSheet.pack(scaled, columns: cols, gap: max(0, gap))
        let size = scaled.first.map { "\($0.width)×\($0.height)" } ?? "—"
        return SpinResult(
            frames: scaled,
            angles: angles,
            sheet: sheet,
            pivotX: pivotX * scale,
            pivotY: pivotY * scale,
            summary: "\(summary) · cell \(size)",
            warning: warning,
            pitchDegrees: pitchDegrees,
            pixelScale: scale,
            columns: cols,
            gap: max(0, gap)
        )
    }

    private static func summary(build: VoxelBuild, frames: Int, pitch: Float) -> String {
        "\(build.note) · \(frames) frames · \(Int(pitch.rounded()))° camera"
    }
}
