import AppKit
import PixelRotatorCore

final class SpriteView: NSView {
    var image: PixelImage?
    var zoom = 3
    var drawsChecker = true
    var showsMessage = false
    var onScrubBegan: (() -> Void)?
    var onScrub: ((Int) -> Void)?
    private var dragAccum: CGFloat = 0

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        if drawsChecker {
            fillChecker(context, in: bounds)
        } else {
            context.setFillColor(NSColor.controlBackgroundColor.cgColor)
            context.fill(bounds)
        }
        guard let image, let cgImage = image.cgImage() else {
            if showsMessage { drawPlaceholder() }
            return
        }
        let scale = fittingZoom(for: image)
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        let originX = drawsChecker ? (bounds.width - width) / 2 : 16
        let originY = drawsChecker ? (bounds.height - height) / 2 : 16
        context.saveGState()
        context.translateBy(x: originX, y: originY + height)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        dragAccum = 0
        onScrubBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        dragAccum += event.deltaX
        let steps = Int(dragAccum / 10)
        guard steps != 0 else { return }
        dragAccum -= CGFloat(steps) * 10
        onScrub?(steps)
    }

    private func fittingZoom(for image: PixelImage) -> CGFloat {
        let requested = CGFloat(max(1, zoom))
        guard drawsChecker else { return requested }
        let limitW = max(1, bounds.width - 32) / CGFloat(image.width)
        let limitH = max(1, bounds.height - 32) / CGFloat(image.height)
        let fitted = max(1, floor(min(limitW, limitH)))
        return min(requested, fitted)
    }

    private func fillChecker(_ context: CGContext, in rect: CGRect) {
        context.setFillColor(CGColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1))
        context.fill(rect)
        let cell: CGFloat = 14
        var row = 0
        var y: CGFloat = 0
        while y < rect.height {
            var column = 0
            var x: CGFloat = 0
            while x < rect.width {
                let shade: CGFloat = (row + column).isMultiple(of: 2) ? 0.10 : 0.13
                context.setFillColor(CGColor(gray: shade, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: cell, height: cell))
                x += cell
                column += 1
            }
            y += cell
            row += 1
        }
    }

    private func drawPlaceholder() {
        guard drawsChecker else { return }
        let text = "Add a front, a side, and a top" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.88),
        ]
        let size = text.size(withAttributes: attributes)
        let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        text.draw(at: point, withAttributes: attributes)
    }
}

final class FaceCard: NSView {
    var onPick: () -> Void = {}
    var onFlip: () -> Void = {}
    var onClear: () -> Void = {}
    var onDropFiles: ([URL]) -> Void = { _ in }

    private let preview = SpriteView()
    private let titleField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")
    private let hintField = NSTextField(labelWithString: "")
    private let flipButton = NSButton()
    private let clearButton = NSButton()
    private let emptyMark = NSImageView()
    private let openButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        registerForDraggedTypes([.fileURL])

        preview.drawsChecker = true
        preview.zoom = 2
        emptyMark.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        emptyMark.contentTintColor = .secondaryLabelColor
        emptyMark.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)

        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        detailField.font = .systemFont(ofSize: 11)
        detailField.textColor = .secondaryLabelColor
        hintField.font = .systemFont(ofSize: 10)
        hintField.textColor = .tertiaryLabelColor
        hintField.lineBreakMode = .byTruncatingTail

        configureIcon(flipButton, symbol: "arrow.left.and.right", action: #selector(flip))
        configureIcon(clearButton, symbol: "xmark", action: #selector(clear))
        flipButton.toolTip = "Flip horizontally"
        clearButton.toolTip = "Remove"

        let titles = NSStackView(views: [titleField, detailField])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 1
        let header = NSStackView(views: [titles, flipButton, clearButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 4

        let column = NSStackView(views: [preview, header, hintField])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        openButton.title = ""
        openButton.isBordered = false
        openButton.bezelStyle = .shadowlessSquare
        openButton.alphaValue = 0.02
        openButton.target = self
        openButton.action = #selector(picked)
        openButton.translatesAutoresizingMaskIntoConstraints = false

        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        addSubview(openButton)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            preview.heightAnchor.constraint(equalToConstant: 86),
            preview.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -16),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            openButton.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            openButton.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
            openButton.topAnchor.constraint(equalTo: preview.topAnchor),
            openButton.bottomAnchor.constraint(equalTo: preview.bottomAnchor),
        ])
        emptyMark.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyMark)
        NSLayoutConstraint.activate([
            emptyMark.centerXAnchor.constraint(equalTo: preview.centerXAnchor),
            emptyMark.centerYAnchor.constraint(equalTo: preview.centerYAnchor),
            emptyMark.widthAnchor.constraint(equalToConstant: 28),
            emptyMark.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show(slot: FaceSlot) {
        titleField.stringValue = slot.face.title
        hintField.stringValue = slot.face.hint
        toolTip = slot.face.hint
        if let image = slot.image {
            preview.image = slot.flipX ? image.flippedHorizontally() : image
            preview.zoom = max(1, min(5, 78 / max(image.height, 1)))
            detailField.stringValue = "\(image.width)×\(image.height)"
            emptyMark.isHidden = true
            flipButton.isHidden = false
            clearButton.isHidden = false
        } else {
            preview.image = nil
            detailField.stringValue = "Drop or click"
            emptyMark.isHidden = false
            flipButton.isHidden = true
            clearButton.isHidden = true
        }
        preview.needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit === emptyMark || hit === preview { return openButton }
        return hit
    }

    @objc private func picked() { onPick() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderColor = NSColor.separatorColor.cgColor
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDropFiles(urls)
        return true
    }

    @objc private func flip() { onFlip() }
    @objc private func clear() { onClear() }

    private func configureIcon(_ button: NSButton, symbol: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.setButtonType(.momentaryChange)
    }
}

final class DrawingRow: NSView, NSTextFieldDelegate {
    var onAngle: (Double) -> Void = { _ in }
    var onFlip: () -> Void = {}
    var onRemove: () -> Void = {}

    private let preview = SpriteView()
    private let nameField = NSTextField(labelWithString: "")
    private let angleField = NSTextField()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        preview.drawsChecker = true
        preview.zoom = 2
        nameField.font = .systemFont(ofSize: 13, weight: .medium)
        nameField.lineBreakMode = .byTruncatingTail
        angleField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        angleField.alignment = .right
        angleField.delegate = self
        angleField.isEditable = true
        angleField.isBezeled = true

        let angleLabel = NSTextField(labelWithString: "Angle")
        angleLabel.font = .systemFont(ofSize: 12)
        angleLabel.textColor = .secondaryLabelColor
        let degree = NSTextField(labelWithString: "°")
        degree.textColor = .secondaryLabelColor
        let angleRow = NSStackView(views: [angleLabel, angleField, degree])
        angleRow.orientation = .horizontal
        angleRow.spacing = 4
        angleField.widthAnchor.constraint(equalToConstant: 52).isActive = true

        let text = NSStackView(views: [nameField, angleRow])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4

        let flip = iconButton("arrow.left.and.right", #selector(flip))
        let remove = iconButton("trash", #selector(remove))
        flip.toolTip = "Flip horizontally"
        remove.toolTip = "Remove"

        let row = NSStackView(views: [preview, text, flip, remove])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            preview.widthAnchor.constraint(equalToConstant: 64),
            preview.heightAnchor.constraint(equalToConstant: 64),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show(slot: DrawingSlot) {
        nameField.stringValue = slot.name ?? "Drawing"
        angleField.stringValue = String(Int(slot.angle.rounded()))
        if let image = slot.image {
            preview.image = slot.flipX ? image.flippedHorizontally() : image
            preview.zoom = max(1, min(3, 56 / max(image.height, 1)))
        } else {
            preview.image = nil
        }
        preview.needsDisplay = true
    }

    func controlTextDidChange(_ obj: Notification) {
        onAngle(angleField.doubleValue)
    }

    @objc private func flip() { onFlip() }
    @objc private func remove() { onRemove() }

    private func iconButton(_ symbol: String, _ action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.bezelStyle = .inline
        button.isBordered = false
        button.target = self
        button.action = action
        button.setButtonType(.momentaryChange)
        return button
    }
}

@MainActor
func fileURLs(from info: NSDraggingInfo) -> [URL] {
    info.draggingPasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]
    ) as? [URL] ?? []
}

@MainActor
func wrappingLabel(_ text: String, size: CGFloat = 13, color: NSColor = .secondaryLabelColor) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.font = .systemFont(ofSize: size)
    field.textColor = color
    field.maximumNumberOfLines = 0
    field.preferredMaxLayoutWidth = 240
    return field
}

final class AngleDialView: NSView {
    var angle = 0.0 {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 36, height: 36) }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 3
        context.setStrokeColor(NSColor.secondaryLabelColor.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        let theta = (90 - angle) * .pi / 180
        let end = CGPoint(
            x: center.x + CGFloat(cos(theta)) * radius,
            y: center.y + CGFloat(sin(theta)) * radius
        )
        context.setStrokeColor(NSColor.systemYellow.cgColor)
        context.setLineWidth(2)
        context.move(to: center)
        context.addLine(to: end)
        context.strokePath()
        context.setFillColor(NSColor.labelColor.cgColor)
        context.fillEllipse(in: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4))
    }
}

final class DropHost: NSView {
    var onDropFiles: ([URL]) -> Void = { _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDropFiles(urls)
        return true
    }
}

@MainActor
func sectionTitle(_ text: String) -> NSTextField {
    let field = NSTextField(labelWithString: text.uppercased())
    field.font = .systemFont(ofSize: 11, weight: .semibold)
    field.textColor = .secondaryLabelColor
    return field
}
