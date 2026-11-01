import AppKit
import PixelRotatorCore
import UniformTypeIdentifiers

struct FaceSlot: Identifiable {
    var face: OrthoFace
    var image: PixelImage?
    var name: String?
    var flipX = false

    var id: OrthoFace { face }
}

struct DrawingSlot: Identifiable {
    var id = UUID()
    var angle = 0.0
    var image: PixelImage?
    var name: String?
    var flipX = false
}

@MainActor
@Observable
final class StudioModel {
    var source: SpinSource = .blueprints
    var slots: [FaceSlot] = OrthoFace.gallery.map { FaceSlot(face: $0) }
    var drawings: [DrawingSlot] = []

    var steps = 32.0
    var pitch = 34.0
    var pixelScale = 1.0
    var magnification = 4.0
    var columns = 8.0
    var gap = 0.0
    var thickness = 10.0
    var maxAxis = 112.0
    var shading = true
    var outline = true
    var mirrorSides = true
    var mirrorDrawings = true
    var keyBackground = true
    var keyTolerance = 28.0
    var inbetween: Inbetween = .dither

    var showSheet = false
    var playing = true
    var frameIndex = 0
    var result = SpinResult.empty
    var isRendering = false
    var statusMessage: String?
    var isDemo = false
    var onSlots: (() -> Void)?
    var onUpdate: (() -> Void)?

    private var rebuildToken = 0

    init() {
        installDemo()
    }

    func start() {
        onSlots?()
        scheduleRebuild()
    }

    var currentFrame: PixelImage? {
        guard result.frames.indices.contains(frameIndex) else { return result.frames.first }
        return result.frames[frameIndex]
    }

    var currentAngle: Float {
        guard result.angles.indices.contains(frameIndex) else { return 0 }
        return result.angles[frameIndex]
    }

    func loadDemo() {
        installDemo()
        onSlots?()
        scheduleRebuild()
    }

    private func installDemo() {
        let views = DemoTaxi.blueprints()
        for index in slots.indices {
            slots[index].image = views[slots[index].face]
            slots[index].name = "Demo"
            slots[index].flipX = false
        }
        source = .blueprints
        isDemo = true
        statusMessage = "Demo taxi. Drop your own views to replace it."
    }

    func clearAll() {
        for index in slots.indices {
            slots[index].image = nil
            slots[index].name = nil
            slots[index].flipX = false
        }
        drawings.removeAll()
        isDemo = false
        statusMessage = nil
        onSlots?()
        scheduleRebuild()
    }

    func clear(face: OrthoFace) {
        guard let index = slots.firstIndex(where: { $0.face == face }) else { return }
        slots[index].image = nil
        slots[index].name = nil
        slots[index].flipX = false
        isDemo = false
        onSlots?()
        scheduleRebuild()
    }

    func toggleFlip(face: OrthoFace) {
        guard let index = slots.firstIndex(where: { $0.face == face }) else { return }
        slots[index].flipX.toggle()
        isDemo = false
        onSlots?()
        scheduleRebuild()
    }

    func toggleFlip(drawing id: UUID) {
        guard let index = drawings.firstIndex(where: { $0.id == id }) else { return }
        drawings[index].flipX.toggle()
        onSlots?()
        scheduleRebuild()
    }

    func setAngle(_ angle: Double, for id: UUID) {
        guard let index = drawings.firstIndex(where: { $0.id == id }) else { return }
        drawings[index].angle = angle
        scheduleRebuild()
    }

    func removeDrawing(_ id: UUID) {
        drawings.removeAll { $0.id == id }
        onSlots?()
        scheduleRebuild()
    }

    func stepFrame(_ delta: Int) {
        let count = result.frames.count
        guard count > 0 else { return }
        frameIndex = (frameIndex + delta % count + count) % count
        onUpdate?()
    }

    func wrappedFrame(_ index: Int) -> Int {
        let count = result.frames.count
        guard count > 0 else { return 0 }
        let value = index % count
        return value >= 0 ? value : value + count
    }

    func scheduleRebuild() {
        rebuildToken += 1
        let token = rebuildToken
        let job = makeJob()
        isRendering = true
        onUpdate?()
        trace("rebuild scheduled token \(token) views \(job.views.count)")
        // AppKit's run loop does not reliably drain a Swift Task started during
        // launch, so the turntable is built on a GCD queue instead.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            trace("rebuild firing token \(token)")
            guard let self, token == self.rebuildToken else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let output = job.run()
                trace("rebuild done frames \(output.frames.count)")
                DispatchQueue.main.async {
                    guard token == self.rebuildToken else { return }
                    self.result = output
                    if self.frameIndex >= self.result.frames.count {
                        self.frameIndex = 0
                    }
                    self.isRendering = false
                    self.onUpdate?()
                }
            }
        }
    }

    func pickFiles(preferred: OrthoFace?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .bmp, .webP]
        panel.allowsMultipleSelection = preferred == nil
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in
                self?.importFiles(urls, preferred: preferred)
            }
        }
    }

    func readDrop(_ providers: [NSItemProvider], preferred: OrthoFace?) -> Bool {
        guard !providers.isEmpty else { return false }
        let batch = DropBatch(total: providers.count)
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                let url: URL?
                if let foundURL = item as? URL {
                    url = foundURL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }
                let resolved = url
                DispatchQueue.main.async {
                    if let resolved { batch.urls.append(resolved) }
                    batch.finished += 1
                    if batch.finished == batch.total {
                        self?.importFiles(batch.urls, preferred: preferred)
                    }
                }
            }
        }
        return true
    }

    func importFiles(_ urls: [URL], preferred: OrthoFace?) {
        guard !urls.isEmpty else { return }
        Task {
            var loaded: [(name: String, image: PixelImage)] = []
            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let image = try ImageCoding.decode(data)
                    loaded.append((url.deletingPathExtension().lastPathComponent, image))
                } catch {
                    statusMessage = error.localizedDescription
                }
            }
            guard !loaded.isEmpty else { return }
            receive(loaded, preferred: preferred)
        }
    }

    func exportSheet() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "rotation-sprite-sheet.png"
        panel.title = "Export Sprite Sheet"
        panel.prompt = "Export"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.writeSheet(to: url)
            }
        }
    }

    func exportGIF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = "rotation.gif"
        panel.title = "Export GIF"
        panel.prompt = "Export"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.writeGIF(to: url)
            }
        }
    }

    private func writeSheet(to url: URL) {
        guard !result.frames.isEmpty else { return }
        do {
            try ImageCoding.writePNG(result.sheet, to: url)
            let manifest = SpriteFactory.manifest(for: result, imageName: url.lastPathComponent)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            let jsonURL = url.deletingPathExtension().appendingPathExtension("json")
            try data.write(to: jsonURL)
            statusMessage = "Saved \(url.lastPathComponent) and \(jsonURL.lastPathComponent)."
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func writeGIF(to url: URL) {
        guard !result.frames.isEmpty else { return }
        do {
            let fps = Double(result.frames.count) / 2.2
            try ImageCoding.writeGIF(result.frames, fps: fps, to: url)
            statusMessage = "Saved \(url.lastPathComponent)."
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func receive(_ loaded: [(name: String, image: PixelImage)], preferred: OrthoFace?) {
        isDemo = false
        if let preferred, loaded.count == 1 {
            assign(loaded[0], to: preferred)
            onSlots?()
            scheduleRebuild()
            return
        }

        if source == .drawings {
            appendDrawings(loaded)
            onSlots?()
            scheduleRebuild()
            return
        }

        var extras: [(name: String, image: PixelImage)] = []
        for item in loaded {
            if let face = Self.guessFace(item.name), slots.contains(where: { $0.face == face }) {
                assign(item, to: face)
            } else {
                extras.append(item)
            }
        }
        for item in extras {
            if let face = slots.first(where: { $0.image == nil })?.face {
                assign(item, to: face)
            } else {
                appendDrawings([item])
                statusMessage = "Extra files were added under Drawn angles."
            }
        }
        onSlots?()
        scheduleRebuild()
    }

    private func assign(_ item: (name: String, image: PixelImage), to face: OrthoFace) {
        guard let index = slots.firstIndex(where: { $0.face == face }) else { return }
        slots[index].image = item.image
        slots[index].name = item.name
        slots[index].flipX = false
    }

    private func appendDrawings(_ items: [(name: String, image: PixelImage)]) {
        let spacing = items.count > 1 && drawings.isEmpty ? 360.0 / Double(items.count) : 45.0
        for (offset, item) in items.enumerated() {
            var slot = DrawingSlot()
            slot.angle = drawings.isEmpty ? spacing * Double(offset) : Double(drawings.count) * 45
            slot.image = item.image
            slot.name = item.name
            drawings.append(slot)
        }
        if source != .drawings && slots.allSatisfy({ $0.image != nil }) {
            source = .drawings
        }
    }

    private func makeJob() -> RenderJob {
        switch source {
        case .blueprints:
            var views: [OrthoFace: PixelImage] = [:]
            for slot in slots {
                if let image = prepared(slot.image, flipX: slot.flipX) {
                    views[slot.face] = image
                }
            }
            return RenderJob(
                source: .blueprints,
                views: views,
                drawings: [],
                mirrorSides: mirrorSides,
                mirrorDrawings: mirrorDrawings,
                thickness: Int(thickness),
                maxAxis: Int(maxAxis),
                steps: Int(steps),
                pitchDegrees: Float(pitch),
                shading: shading,
                outline: outline,
                inbetween: inbetween,
                pixelScale: Int(pixelScale),
                columns: Int(columns),
                gap: Int(gap)
            )
        case .drawings:
            let frames = drawings.compactMap { slot -> AngleDrawing? in
                guard let image = prepared(slot.image, flipX: slot.flipX) else { return nil }
                return AngleDrawing(angleDegrees: Float(slot.angle), image: image)
            }
            return RenderJob(
                source: .drawings,
                views: [:],
                drawings: frames,
                mirrorSides: mirrorSides,
                mirrorDrawings: mirrorDrawings,
                thickness: Int(thickness),
                maxAxis: Int(maxAxis),
                steps: Int(steps),
                pitchDegrees: Float(pitch),
                shading: shading,
                outline: outline,
                inbetween: inbetween,
                pixelScale: Int(pixelScale),
                columns: Int(columns),
                gap: Int(gap)
            )
        }
    }

    private func prepared(_ image: PixelImage?, flipX: Bool) -> PixelImage? {
        guard var image else { return nil }
        if flipX {
            image = image.flippedHorizontally()
        }
        if keyBackground, !image.hasTransparency() {
            image = image.keyingOutCorner(tolerance: Int(keyTolerance))
        }
        return image
    }

    static func guessFace(_ name: String) -> OrthoFace? {
        let tokens = name.lowercased().split { !$0.isLetter }.map(String.init)
        let table: [(String, OrthoFace)] = [
            ("bottom", .bottom),
            ("under", .bottom),
            ("underside", .bottom),
            ("front", .front),
            ("back", .back),
            ("rear", .back),
            ("right", .right),
            ("left", .left),
            ("top", .top),
            ("above", .top),
            ("side", .right),
        ]
        for token in tokens {
            if let match = table.first(where: { token == $0.0 || token.hasPrefix($0.0) }) {
                return match.1
            }
        }
        return nil
    }
}

private final class DropBatch: @unchecked Sendable {
    var urls: [URL] = []
    var finished = 0
    let total: Int
    init(total: Int) { self.total = total }
}

private struct RenderJob: Sendable {
    var source: SpinSource
    var views: [OrthoFace: PixelImage]
    var drawings: [AngleDrawing]
    var mirrorSides: Bool
    var mirrorDrawings: Bool
    var thickness: Int
    var maxAxis: Int
    var steps: Int
    var pitchDegrees: Float
    var shading: Bool
    var outline: Bool
    var inbetween: Inbetween
    var pixelScale: Int
    var columns: Int
    var gap: Int

    func run() -> SpinResult {
        switch source {
        case .blueprints:
            SpriteFactory.spinBlueprints(
                views: views,
                mirrorSides: mirrorSides,
                thickness: thickness,
                maxAxis: maxAxis,
                steps: steps,
                pitchDegrees: pitchDegrees,
                shading: shading,
                outline: outline,
                pixelScale: pixelScale,
                columns: columns,
                gap: gap
            )
        case .drawings:
            SpriteFactory.spinDrawings(
                drawings: drawings,
                steps: steps,
                mirrorOtherSide: mirrorDrawings,
                inbetween: inbetween,
                outline: outline,
                pixelScale: pixelScale,
                columns: columns,
                gap: gap
            )
        }
    }
}
