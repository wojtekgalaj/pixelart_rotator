import AppKit
import PixelRotatorCore

final class RotatorWindow: NSWindow {
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49, !(firstResponder is NSText) {
            (windowController as? MainWindowController)?.togglePlay(nil)
            return
        }
        super.keyDown(with: event)
    }
}

final class MainWindowController: NSWindowController, NSToolbarDelegate, NSSplitViewDelegate {
    let studio = StudioModel()

    private let split = NSSplitView()
    private let sourceControl = NSSegmentedControl(labels: ["Flat views", "Drawn angles"], trackingMode: .selectOne, target: nil, action: nil)
    private let blurb = wrappingLabel("")
    private let slotStack = NSStackView()
    private let noteLabel = wrappingLabel("Name files front, right, top, bottom, back, or left and drop them together.\n\nTransparent pixels are cut away. Paint windows and lights. A clear pixel is a hole through the whole object.", size: 11)
    private let stage = SpriteView()
    private let sheetView = SpriteView()
    private let sheetScroll = NSScrollView()
    private let previewMode = NSSegmentedControl(labels: ["Turntable", "Sprite sheet"], trackingMode: .selectOne, target: nil, action: nil)
    private let summaryLabel = NSTextField(labelWithString: "")
    private let warningLabel = wrappingLabel("", size: 12, color: .systemOrange)
    private let spinner = NSProgressIndicator()
    private let playButton = NSButton()
    private let frameSlider = NSSlider()
    private let frameLabel = NSTextField(labelWithString: "No frames")
    private let dial = AngleDialView()
    private let zoomStepper = NSStepper()
    private let demoBanner = NSTextField(labelWithString: "Demo taxi — drop your drawings on the left")
    private let blueprintBox = NSStackView()
    private let drawingBox = NSStackView()
    private let pitchCaption = wrappingLabel("", size: 11)
    private let inbetweenCaption = wrappingLabel("", size: 11)
    private let frameStat = NSTextField(labelWithString: "—")
    private let sheetStat = NSTextField(labelWithString: "—")
    private let countStat = NSTextField(labelWithString: "—")
    private let pivotStat = NSTextField(labelWithString: "—")
    private let statusLabel = wrappingLabel("", size: 11)
    private let exportButton = NSButton()
    private let gifButton = NSButton()
    private var toolbarExport: NSToolbarItem?
    private var toolbarGIF: NSToolbarItem?
    private var timer: Timer?
    private var timerCount = -1
    private var didSnapshot = false

    private let stepsValue = NSTextField(labelWithString: "32")
    private let pitchValue = NSTextField(labelWithString: "34°")
    private let scaleValue = NSTextField(labelWithString: "1×")
    private let columnsValue = NSTextField(labelWithString: "8")
    private let gapValue = NSTextField(labelWithString: "0 px")
    private let thicknessValue = NSTextField(labelWithString: "10")
    private let detailValue = NSTextField(labelWithString: "112")
    private let keyValue = NSTextField(labelWithString: "28")
    private let inbetweenPopup = NSPopUpButton()
    private let keySliderRow = NSStackView()

    init() {
        let window = RotatorWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "Pixel Rotator"
        window.subtitle = "Sprite sheets from flat pixel art"
        window.minSize = NSSize(width: 1080, height: 680)
        window.setFrameAutosaveName("PixelRotatorWindow")
        window.toolbarStyle = .unified
        window.toolbar = makeToolbar()
        buildInterface()
        studio.onSlots = { [weak self] in self?.reloadSlots() }
        studio.onUpdate = { [weak self] in self?.reloadPreview() }
        studio.start()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        split.setPosition(380, ofDividerAt: 0)
        if let width = window?.contentView?.bounds.width {
            split.setPosition(width - 300, ofDividerAt: 1)
        }
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        dividerIndex == 0 ? 300 : 720
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        dividerIndex == 0 ? 480 : splitView.bounds.width - 260
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }

    @objc func loadDemo(_ sender: Any?) { studio.loadDemo() }
    @objc func clearAll(_ sender: Any?) { studio.clearAll() }
    @objc func exportSheet(_ sender: Any?) { studio.exportSheet() }
    @objc func exportGIF(_ sender: Any?) { studio.exportGIF() }
    @objc func addDrawings() { studio.pickFiles(preferred: nil) }

    @objc func togglePlay(_ sender: Any?) {
        studio.playing.toggle()
        timerCount = -1
        syncTimer()
        updatePlayButton()
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(exportSheet) || menuItem.action == #selector(exportGIF) {
            return !studio.result.frames.isEmpty
        }
        return true
    }

    private func buildInterface() {
        let left = NSView()
        let center = NSView()
        let right = NSView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = self
        split.autosaveName = "PixelRotatorSplit"
        split.addSubview(left)
        split.addSubview(center)
        split.addSubview(right)
        split.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 0)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        split.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 2)
        window?.contentView = split

        buildLeft(in: left)
        buildCenter(in: center)
        buildRight(in: right)
        reloadSlots()
    }

    private func buildLeft(in pane: NSView) {
        let title = NSTextField(labelWithString: "Source")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        sourceControl.selectedSegment = 0
        sourceControl.target = self
        sourceControl.action = #selector(sourceChanged(_:))
        blurb.preferredMaxLayoutWidth = 340

        let header = NSStackView(views: [title, sourceControl, blurb])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 8
        header.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 12, right: 16)
        header.translatesAutoresizingMaskIntoConstraints = false

        slotStack.orientation = .vertical
        slotStack.alignment = .leading
        slotStack.spacing = 12
        slotStack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 16, right: 16)
        slotStack.translatesAutoresizingMaskIntoConstraints = false

        let host = DropHost()
        host.onDropFiles = { [weak self] urls in self?.studio.importFiles(urls, preferred: nil) }
        host.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(slotStack)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = host
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let rule = NSBox()
        rule.boxType = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false

        pane.addSubview(header)
        pane.addSubview(rule)
        pane.addSubview(scroll)

        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: pane.topAnchor),
            header.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            rule.topAnchor.constraint(equalTo: header.bottomAnchor),
            rule.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: rule.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
            host.topAnchor.constraint(equalTo: clip.topAnchor),
            host.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            slotStack.topAnchor.constraint(equalTo: host.topAnchor),
            slotStack.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            slotStack.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            slotStack.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            slotStack.widthAnchor.constraint(equalTo: clip.widthAnchor),
        ])
    }

    private func buildCenter(in pane: NSView) {
        previewMode.selectedSegment = 0
        previewMode.target = self
        previewMode.action = #selector(previewModeChanged(_:))
        summaryLabel.font = .systemFont(ofSize: 11)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let top = NSStackView(views: [previewMode, spinner, summaryLabel])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 10
        top.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        top.translatesAutoresizingMaskIntoConstraints = false
        previewMode.setContentHuggingPriority(.required, for: .horizontal)

        stage.showsMessage = true
        stage.onScrubBegan = { [weak self] in
            self?.studio.playing = false
            self?.timerCount = -1
            self?.syncTimer()
            self?.updatePlayButton()
        }
        stage.onScrub = { [weak self] delta in
            self?.studio.stepFrame(delta)
        }

        sheetView.drawsChecker = true
        sheetScroll.hasVerticalScroller = true
        sheetScroll.hasHorizontalScroller = true
        sheetScroll.drawsBackground = false
        sheetScroll.documentView = sheetView
        sheetScroll.isHidden = true
        sheetScroll.translatesAutoresizingMaskIntoConstraints = false
        stage.translatesAutoresizingMaskIntoConstraints = false

        demoBanner.font = .systemFont(ofSize: 12, weight: .medium)
        demoBanner.textColor = NSColor.white.withAlphaComponent(0.92)
        demoBanner.drawsBackground = true
        demoBanner.backgroundColor = NSColor.black.withAlphaComponent(0.45)
        demoBanner.isBezeled = false
        demoBanner.isEditable = false
        demoBanner.alignment = .center
        demoBanner.wantsLayer = true
        demoBanner.layer?.cornerRadius = 10
        demoBanner.translatesAutoresizingMaskIntoConstraints = false

        warningLabel.translatesAutoresizingMaskIntoConstraints = false
        let transport = makeTransport()
        transport.translatesAutoresizingMaskIntoConstraints = false

        pane.addSubview(top)
        pane.addSubview(stage)
        pane.addSubview(sheetScroll)
        pane.addSubview(demoBanner)
        pane.addSubview(warningLabel)
        pane.addSubview(transport)

        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: pane.topAnchor),
            top.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            stage.topAnchor.constraint(equalTo: top.bottomAnchor),
            stage.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            sheetScroll.topAnchor.constraint(equalTo: stage.topAnchor),
            sheetScroll.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            sheetScroll.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            sheetScroll.bottomAnchor.constraint(equalTo: stage.bottomAnchor),
            demoBanner.topAnchor.constraint(equalTo: stage.topAnchor, constant: 12),
            demoBanner.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            warningLabel.topAnchor.constraint(equalTo: stage.bottomAnchor, constant: 6),
            warningLabel.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 16),
            warningLabel.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -16),
            transport.topAnchor.constraint(equalTo: warningLabel.bottomAnchor, constant: 4),
            transport.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            transport.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            transport.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
            transport.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    private func makeTransport() -> NSView {
        let symbol = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        playButton.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")?.withSymbolConfiguration(symbol)
        playButton.bezelStyle = .circular
        playButton.target = self
        playButton.action = #selector(togglePlay(_:))
        playButton.toolTip = "Play or pause (space)"

        let previous = NSButton()
        previous.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous frame")
        previous.bezelStyle = .inline
        previous.isBordered = false
        previous.target = self
        previous.action = #selector(stepBack)

        let next = NSButton()
        next.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next frame")
        next.bezelStyle = .inline
        next.isBordered = false
        next.target = self
        next.action = #selector(stepForward)

        frameSlider.minValue = 0
        frameSlider.maxValue = 1
        frameSlider.target = self
        frameSlider.action = #selector(frameMoved(_:))
        frameSlider.isContinuous = true
        frameLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        frameLabel.textColor = .secondaryLabelColor
        frameLabel.alignment = .right
        dial.toolTip = "0° is the front. The needle turns with the object."

        zoomStepper.minValue = 1
        zoomStepper.maxValue = 8
        zoomStepper.increment = 1
        zoomStepper.doubleValue = studio.magnification
        zoomStepper.target = self
        zoomStepper.action = #selector(zoomChanged(_:))
        zoomStepper.toolTip = "Preview zoom. The exported sheet uses Pixel scale."
        let zoomLabel = NSTextField(labelWithString: "Zoom")
        zoomLabel.font = .systemFont(ofSize: 12)
        zoomLabel.textColor = .secondaryLabelColor

        let bar = NSStackView(views: [playButton, previous, dial, next, frameSlider, frameLabel, zoomLabel, zoomStepper])
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 6, left: 16, bottom: 8, right: 16)
        frameLabel.widthAnchor.constraint(equalToConstant: 118).isActive = true
        playButton.widthAnchor.constraint(equalToConstant: 32).isActive = true
        dial.widthAnchor.constraint(equalToConstant: 36).isActive = true
        dial.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return bar
    }

    private func buildRight(in pane: NSView) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        blueprintBox.orientation = .vertical
        blueprintBox.alignment = .leading
        blueprintBox.spacing = 10
        drawingBox.orientation = .vertical
        drawingBox.alignment = .leading
        drawingBox.spacing = 10

        let outline = checkbox("Outline", #selector(outlineChanged(_:)), studio.outline)
        let shade = checkbox("Shade the form", #selector(shadeChanged(_:)), studio.shading)
        let mirrorSides = checkbox("Mirror the missing side", #selector(mirrorSidesChanged(_:)), studio.mirrorSides)
        let key = checkbox("Key out a solid background", #selector(keyChanged(_:)), studio.keyBackground)
        let mirrorDrawings = checkbox("Mirror to the other side", #selector(mirrorDrawingsChanged(_:)), studio.mirrorDrawings)

        inbetweenPopup.addItems(withTitles: Inbetween.allCases.map(\.title))
        inbetweenPopup.target = self
        inbetweenPopup.action = #selector(inbetweenChanged(_:))
        inbetweenCaption.stringValue = "Pixels swap from one drawing to the next and stay hard-edged."

        blueprintBox.addArrangedSubview(sliderRow("Camera", pitchValue, 0, 90, studio.pitch, #selector(pitchMoved(_:))))
        blueprintBox.addArrangedSubview(pitchCaption)
        blueprintBox.addArrangedSubview(shade)
        blueprintBox.addArrangedSubview(mirrorSides)
        blueprintBox.addArrangedSubview(sectionTitle("Model"))
        blueprintBox.addArrangedSubview(sliderRow("Thickness", thicknessValue, 1, 48, studio.thickness, #selector(thicknessMoved(_:))))
        blueprintBox.addArrangedSubview(wrappingLabel("Used when a dimension has no drawing. A front on its own becomes a slab this deep.", size: 11))
        blueprintBox.addArrangedSubview(sliderRow("Detail cap", detailValue, 32, 160, studio.maxAxis, #selector(detailMoved(_:))))
        blueprintBox.addArrangedSubview(key)
        keySliderRow.orientation = .vertical
        keySliderRow.addArrangedSubview(sliderRow("Key tolerance", keyValue, 0, 80, studio.keyTolerance, #selector(keyToleranceMoved(_:))))
        blueprintBox.addArrangedSubview(keySliderRow)

        drawingBox.addArrangedSubview(sectionTitle("In-betweens"))
        drawingBox.addArrangedSubview(inbetweenPopup)
        drawingBox.addArrangedSubview(inbetweenCaption)
        drawingBox.addArrangedSubview(mirrorDrawings)
        drawingBox.addArrangedSubview(wrappingLabel("A drawing at 90° also fills 270°, flipped. 0° is the front and 90° is the right side.", size: 11))
        drawingBox.isHidden = true

        stack.addArrangedSubview(sectionTitle("Rotation"))
        stack.addArrangedSubview(sliderRow("Steps", stepsValue, 4, 128, studio.steps, #selector(stepsMoved(_:))))
        stack.addArrangedSubview(wrappingLabel("How many frames in one full turn.", size: 11))
        stack.addArrangedSubview(blueprintBox)
        stack.addArrangedSubview(drawingBox)
        stack.addArrangedSubview(sectionTitle("Sprite sheet"))
        stack.addArrangedSubview(sliderRow("Pixel scale", scaleValue, 1, 8, studio.pixelScale, #selector(scaleMoved(_:))))
        stack.addArrangedSubview(sliderRow("Columns", columnsValue, 1, 32, studio.columns, #selector(columnsMoved(_:))))
        stack.addArrangedSubview(sliderRow("Gap", gapValue, 0, 8, studio.gap, #selector(gapMoved(_:))))
        stack.addArrangedSubview(outline)
        stack.addArrangedSubview(sectionTitle("This export"))
        stack.addArrangedSubview(statRow("Frame", frameStat))
        stack.addArrangedSubview(statRow("Sheet", sheetStat))
        stack.addArrangedSubview(statRow("Frames", countStat))
        stack.addArrangedSubview(statRow("Pivot", pivotStat))
        stack.addArrangedSubview(statusLabel)
        for view in [stack, blueprintBox, drawingBox, keySliderRow] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        stack.widthAnchor.constraint(equalToConstant: 268).isActive = true
        blueprintBox.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        drawingBox.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = stack
        scroll.translatesAutoresizingMaskIntoConstraints = false

        exportButton.title = "Export Sprite Sheet"
        exportButton.bezelStyle = .rounded
        exportButton.controlSize = .large
        exportButton.target = self
        exportButton.action = #selector(exportSheet(_:))
        exportButton.keyEquivalent = "\r"
        gifButton.title = "Export GIF"
        gifButton.bezelStyle = .rounded
        gifButton.target = self
        gifButton.action = #selector(exportGIF(_:))
        let buttons = NSStackView(views: [exportButton, gifButton])
        buttons.orientation = .vertical
        buttons.spacing = 8
        buttons.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 16, right: 16)
        buttons.translatesAutoresizingMaskIntoConstraints = false
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        exportButton.widthAnchor.constraint(equalTo: buttons.widthAnchor, constant: -32).isActive = true

        let rule = NSBox()
        rule.boxType = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false

        pane.addSubview(scroll)
        pane.addSubview(rule)
        pane.addSubview(buttons)
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: pane.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            rule.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            rule.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            buttons.topAnchor.constraint(equalTo: rule.bottomAnchor),
            buttons.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            buttons.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            buttons.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
            stack.topAnchor.constraint(equalTo: clip.topAnchor),
            stack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            stack.bottomAnchor.constraint(equalTo: clip.bottomAnchor).withPriority(.defaultLow),
        ])
        pitchCaption.stringValue = pitchText(studio.pitch)
    }

    private func reloadSlots() {
        sourceControl.selectedSegment = studio.source == .blueprints ? 0 : 1
        blurb.stringValue = studio.source == .blueprints
            ? "Draw the flat sides. Empty slots are skipped. The app builds a solid object and turns it."
            : "Upload sprites you already painted. Add as many angles as you want, then pick how many frames the turn has."
        blueprintBox.isHidden = studio.source != .blueprints
        drawingBox.isHidden = studio.source != .drawings
        slotStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if studio.source == .blueprints {
            var cards: [NSView] = []
            for slot in studio.slots {
                let card = FaceCard()
                card.show(slot: slot)
                let face = slot.face
                card.onPick = { [weak self] in self?.studio.pickFiles(preferred: face) }
                card.onFlip = { [weak self] in self?.studio.toggleFlip(face: face) }
                card.onClear = { [weak self] in self?.studio.clear(face: face) }
                card.onDropFiles = { [weak self] urls in self?.studio.importFiles(urls, preferred: face) }
                cards.append(card)
            }
            var rows: [[NSView]] = []
            var index = 0
            while index < cards.count {
                let end = min(index + 2, cards.count)
                rows.append(Array(cards[index..<end]))
                index = end
            }
            let grid = NSGridView(views: rows)
            grid.xPlacement = .fill
            grid.yPlacement = .fill
            grid.rowSpacing = 10
            grid.columnSpacing = 10
            grid.translatesAutoresizingMaskIntoConstraints = false
            slotStack.addArrangedSubview(grid)
            grid.widthAnchor.constraint(equalTo: slotStack.widthAnchor, constant: -32).isActive = true
        } else {
            for slot in studio.drawings {
                let row = DrawingRow()
                row.show(slot: slot)
                let id = slot.id
                row.onAngle = { [weak self] angle in self?.studio.setAngle(angle, for: id) }
                row.onFlip = { [weak self] in self?.studio.toggleFlip(drawing: id) }
                row.onRemove = { [weak self] in self?.studio.removeDrawing(id) }
                slotStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: slotStack.widthAnchor, constant: -32).isActive = true
            }
            let add = NSButton(title: "Add drawings", target: self, action: #selector(addDrawings))
            add.bezelStyle = .rounded
            slotStack.addArrangedSubview(add)
        }
        slotStack.addArrangedSubview(noteLabel)
        noteLabel.widthAnchor.constraint(equalTo: slotStack.widthAnchor, constant: -32).isActive = true
    }

    private func reloadPreview() {
        summaryLabel.stringValue = studio.result.summary
        warningLabel.stringValue = studio.result.warning ?? ""
        warningLabel.isHidden = studio.result.warning == nil
        if studio.isRendering {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
        let count = studio.result.frames.count
        frameSlider.isEnabled = count > 1
        frameSlider.maxValue = Double(max(count - 1, 0))
        if !frameSlider.isHighlighted {
            frameSlider.doubleValue = Double(studio.frameIndex)
        }
        frameLabel.stringValue = count == 0
            ? "No frames"
            : "\(studio.frameIndex + 1)/\(count)  ·  \(Int(studio.currentAngle.rounded()))°"
        demoBanner.isHidden = !studio.isDemo || studio.showSheet
        updatePlayButton()
        updateStats()
        paintFrame()
        syncTimer()
        updateExportEnabled()
        snapshotOnce()
    }

    private func paintFrame() {
        let zoom = Int(studio.magnification)
        stage.zoom = zoom
        stage.image = studio.currentFrame
        stage.needsDisplay = true
        dial.angle = Double(studio.currentAngle)
        guard studio.showSheet else { return }
        sheetView.zoom = max(1, zoom)
        sheetView.image = studio.result.sheet
        let width = max(CGFloat(studio.result.sheet.width) * CGFloat(sheetView.zoom) + 32, 32)
        let height = max(CGFloat(studio.result.sheet.height) * CGFloat(sheetView.zoom) + 32, 32)
        sheetView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        sheetView.needsDisplay = true
    }

    private func updateStats() {
        if let frame = studio.result.frames.first {
            frameStat.stringValue = "\(frame.width) × \(frame.height)"
            sheetStat.stringValue = "\(studio.result.sheet.width) × \(studio.result.sheet.height)"
            countStat.stringValue = "\(studio.result.frames.count)"
            pivotStat.stringValue = "\(studio.result.pivotX), \(studio.result.pivotY)"
        } else {
            frameStat.stringValue = "—"
            sheetStat.stringValue = "—"
            countStat.stringValue = "—"
            pivotStat.stringValue = "—"
        }
        statusLabel.stringValue = studio.statusMessage ?? ""
    }

    private func updatePlayButton() {
        let name = studio.playing ? "pause.fill" : "play.fill"
        let symbol = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        playButton.image = NSImage(systemSymbolName: name, accessibilityDescription: studio.playing ? "Pause" : "Play")?
            .withSymbolConfiguration(symbol)
    }

    private func updateExportEnabled() {
        let enabled = !studio.result.frames.isEmpty
        exportButton.isEnabled = enabled
        gifButton.isEnabled = enabled
        toolbarExport?.isEnabled = enabled
        toolbarGIF?.isEnabled = enabled
    }

    private func syncTimer() {
        let count = studio.result.frames.count
        let shouldRun = studio.playing && count > 1
        if shouldRun, timer != nil, timerCount == count { return }
        timer?.invalidate()
        timer = nil
        timerCount = count
        guard shouldRun else { return }
        let interval = 2.2 / Double(count)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.studio.stepFrame(1)
            }
        }
    }

    private func snapshotOnce() {
        guard !didSnapshot, ProcessInfo.processInfo.environment["PIXEL_ROTATOR_SNAPSHOT"] == "1" else { return }
        guard !studio.result.frames.isEmpty, !studio.isRendering else { return }
        didSnapshot = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.writeSnapshot()
        }
    }

    private func writeSnapshot() {
        guard let window, let view = window.contentView else {
            trace("snapshot: no window")
            return
        }
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let bounds = view.bounds
        trace("snapshot bounds \(bounds) frames \(studio.result.frames.count) rendering \(studio.isRendering)")
        if let rep = view.bitmapImageRepForCachingDisplay(in: bounds) {
            view.cacheDisplay(in: bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/pixel-rotator/ui.png"))
                trace("snapshot wrote cache \(data.count) bytes")
                return
            }
        }
        let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming, .bestResolution]
        )
        guard let image else {
            trace("snapshot: no image")
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/pixel-rotator/ui-window.png"))
            trace("snapshot wrote window \(data.count) bytes")
        }
    }

    @objc private func sourceChanged(_ sender: NSSegmentedControl) {
        studio.source = sender.selectedSegment == 0 ? .blueprints : .drawings
        reloadSlots()
        studio.scheduleRebuild()
    }

    @objc private func previewModeChanged(_ sender: NSSegmentedControl) {
        studio.showSheet = sender.selectedSegment == 1
        stage.isHidden = studio.showSheet
        sheetScroll.isHidden = !studio.showSheet
        demoBanner.isHidden = studio.showSheet || !studio.isDemo
        paintFrame()
    }

    @objc private func frameMoved(_ sender: NSSlider) {
        studio.playing = false
        timer?.invalidate()
        timer = nil
        timerCount = -1
        studio.frameIndex = Int(sender.doubleValue.rounded())
        frameLabel.stringValue = "\(studio.frameIndex + 1)/\(studio.result.frames.count)  ·  \(Int(studio.currentAngle.rounded()))°"
        updatePlayButton()
        paintFrame()
    }

    @objc private func stepBack() {
        studio.playing = false
        timerCount = -1
        studio.stepFrame(-1)
    }

    @objc private func stepForward() {
        studio.playing = false
        timerCount = -1
        studio.stepFrame(1)
    }

    @objc private func zoomChanged(_ sender: NSStepper) {
        studio.magnification = sender.doubleValue
        paintFrame()
    }

    @objc private func stepsMoved(_ sender: NSSlider) { apply(sender, label: stepsValue, suffix: "") { studio.steps = $0 } }
    @objc private func pitchMoved(_ sender: NSSlider) {
        apply(sender, label: pitchValue, suffix: "°") { studio.pitch = $0 }
        pitchCaption.stringValue = pitchText(sender.doubleValue)
    }
    @objc private func scaleMoved(_ sender: NSSlider) { apply(sender, label: scaleValue, suffix: "×") { studio.pixelScale = $0 } }
    @objc private func columnsMoved(_ sender: NSSlider) { apply(sender, label: columnsValue, suffix: "") { studio.columns = $0 } }
    @objc private func gapMoved(_ sender: NSSlider) { apply(sender, label: gapValue, suffix: " px") { studio.gap = $0 } }
    @objc private func thicknessMoved(_ sender: NSSlider) { apply(sender, label: thicknessValue, suffix: "") { studio.thickness = $0 } }
    @objc private func detailMoved(_ sender: NSSlider) { apply(sender, label: detailValue, suffix: "") { studio.maxAxis = $0 } }
    @objc private func keyToleranceMoved(_ sender: NSSlider) { apply(sender, label: keyValue, suffix: "") { studio.keyTolerance = $0 } }

    @objc private func outlineChanged(_ sender: NSButton) { studio.outline = sender.state == .on; studio.scheduleRebuild() }
    @objc private func shadeChanged(_ sender: NSButton) { studio.shading = sender.state == .on; studio.scheduleRebuild() }
    @objc private func mirrorSidesChanged(_ sender: NSButton) { studio.mirrorSides = sender.state == .on; studio.scheduleRebuild() }
    @objc private func mirrorDrawingsChanged(_ sender: NSButton) { studio.mirrorDrawings = sender.state == .on; studio.scheduleRebuild() }
    @objc private func keyChanged(_ sender: NSButton) {
        studio.keyBackground = sender.state == .on
        keySliderRow.isHidden = sender.state != .on
        studio.scheduleRebuild()
    }
    @objc private func inbetweenChanged(_ sender: NSPopUpButton) {
        studio.inbetween = Inbetween.allCases[sender.indexOfSelectedItem]
        switch studio.inbetween {
        case .hold: inbetweenCaption.stringValue = "Each frame uses the nearest drawing."
        case .dither: inbetweenCaption.stringValue = "Pixels swap from one drawing to the next and stay hard-edged."
        case .dissolve: inbetweenCaption.stringValue = "A soft mix. Smoother, and a little blurry."
        }
        studio.scheduleRebuild()
    }

    private func apply(_ sender: NSSlider, label: NSTextField, suffix: String, assign: (Double) -> Void) {
        let value = sender.doubleValue.rounded()
        sender.doubleValue = value
        label.stringValue = "\(Int(value))\(suffix)"
        assign(value)
        studio.scheduleRebuild()
    }

    private func pitchText(_ pitch: Double) -> String {
        switch pitch {
        case 0..<12: "Side-on, like a platformer."
        case 12..<48: "A three-quarter view. Roof and face both show."
        case 48..<78: "High angle, for a top-down game."
        default: "Straight down."
        }
    }

    private func slider(in stack: NSStackView, action: Selector) -> NSSlider {
        for view in stack.arrangedSubviews {
            if let slider = view as? NSSlider, slider.action == action { return slider }
            if let nested = view as? NSStackView, let slider = findSlider(nested, action) { return slider }
        }
        return NSSlider()
    }

    private func findSlider(_ stack: NSStackView, _ action: Selector) -> NSSlider? {
        for view in stack.arrangedSubviews {
            if let slider = view as? NSSlider, slider.action == action { return slider }
            if let nested = view as? NSStackView, let slider = findSlider(nested, action) { return slider }
        }
        return nil
    }

    private func sliderRow(_ title: String, _ value: NSTextField, _ min: Double, _ max: Double, _ current: Double, _ action: Selector) -> NSView {
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 13)
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        value.textColor = .secondaryLabelColor
        value.alignment = .right
        value.stringValue = title == "Pixel scale" ? "\(Int(current))×" : (title == "Camera" ? "\(Int(current))°" : (title == "Gap" ? "\(Int(current)) px" : "\(Int(current))"))
        let header = NSStackView(views: [name, value])
        header.orientation = .horizontal
        header.distribution = .fill
        value.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        let slider = NSSlider(value: current, minValue: min, maxValue: max, target: self, action: action)
        slider.isContinuous = true
        let column = NSStackView(views: [header, slider])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 2
        slider.translatesAutoresizingMaskIntoConstraints = false
        column.widthAnchor.constraint(equalToConstant: 236).isActive = true
        slider.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return column
    }

    private func checkbox(_ title: String, _ action: Selector, _ on: Bool) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.state = on ? .on : .off
        button.font = .systemFont(ofSize: 13)
        return button
    }

    private func statRow(_ title: String, _ value: NSTextField) -> NSView {
        let name = NSTextField(labelWithString: title)
        name.textColor = .secondaryLabelColor
        name.font = .systemFont(ofSize: 13)
        value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        value.alignment = .right
        let row = NSStackView(views: [name, value])
        row.orientation = .horizontal
        return row
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "PixelRotatorToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [NSToolbarItem.Identifier("demo"), NSToolbarItem.Identifier("clear"), .flexibleSpace, NSToolbarItem.Identifier("gif"), NSToolbarItem.Identifier("export")]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self
        switch itemIdentifier.rawValue {
        case "demo":
            item.label = "Demo Taxi"
            item.image = NSImage(systemSymbolName: "car.fill", accessibilityDescription: nil)
            item.action = #selector(loadDemo(_:))
        case "clear":
            item.label = "Clear"
            item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            item.action = #selector(clearAll(_:))
        case "gif":
            item.label = "Export GIF"
            item.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)
            item.action = #selector(exportGIF(_:))
            toolbarGIF = item
        case "export":
            item.label = "Export Sheet"
            item.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
            item.action = #selector(exportSheet(_:))
            toolbarExport = item
        default:
            return nil
        }
        return item
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
