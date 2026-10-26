import AppKit
import Vision

final class OverlayView: NSView, NSTextFieldDelegate {
    enum Phase { case idle, selecting, editing }
    enum Drag { case none, selecting(CGPoint), moving(CGPoint), resizing(Int), drawing }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    weak var controller: CaptureController?
    let image: CGImage
    let renderer: SceneRenderer
    let scale: CGFloat

    var phase: Phase = .idle
    var drag: Drag = .none
    var selection = CGRect.zero
    var annotations: [Annotation] = []
    var current: Annotation?

    var tool: Tool = .move { didSet { refreshBars() } }
    private var history: [[Annotation]] = []   // snapshots for undo (draw, erase)
    private var erasedAny = false
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 3

    private var toolBar: HUDBar!
    private var actionBar: HUDBar!
    private var styleBar: HUDBar!
    private var toolButtons: [Tool: IconButton] = [:]
    private var swatches: [SwatchButton] = []
    private var textField: NSTextField?
    private var textOrigin = CGPoint.zero

    private let palette: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen,
                                      .systemBlue, .systemPurple, .white, .black]

    init(frame: NSRect, image: CGImage) {
        self.image = image
        self.renderer = SceneRenderer(image: image, bounds: CGRect(origin: .zero, size: frame.size))
        self.scale = CGFloat(image.width) / max(1, frame.width)
        super.init(frame: frame)
        buildBars()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) yok") }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        renderer.drawBackground(ctx)

        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        if phase == .idle {
            ctx.fill(bounds)
        } else {
            ctx.addRect(bounds)
            ctx.addRect(selection)
            ctx.fillPath(using: .evenOdd)
        }
        ctx.restoreGState()

        guard phase != .idle else { return }

        ctx.saveGState()
        ctx.clip(to: selection)
        for a in annotations { renderer.draw(a, ctx) }
        if let c = current { renderer.draw(c, ctx) }
        ctx.restoreGState()

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: selection)
        border.lineWidth = 1
        border.stroke()

        if phase == .editing {
            for p in handlePoints() {
                let r = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
                NSColor.white.setFill()
                NSBezierPath(ovalIn: r).fill()
                NSColor.controlAccentColor.setStroke()
                let o = NSBezierPath(ovalIn: r); o.lineWidth = 1.5; o.stroke()
            }
        }
        drawSizeLabel()
    }

    private func drawSizeLabel() {
        let text = "\(Int((selection.width * scale).rounded())) × \(Int((selection.height * scale).rounded()))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attrs)
        var o = CGPoint(x: selection.minX, y: selection.minY - size.height - 10)
        if o.y < 4 { o = CGPoint(x: selection.minX + 6, y: selection.minY + 6) }
        let pill = CGRect(x: o.x, y: o.y, width: size.width + 14, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 7, yRadius: 7).fill()
        text.draw(at: CGPoint(x: pill.minX + 7, y: pill.minY + 2), withAttributes: attrs)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - Mouse / pen

    private func pressure(_ e: NSEvent) -> CGFloat {
        e.subtype == .tabletPoint ? max(0.05, CGFloat(e.pressure)) : -1
    }

    private func penWidth(_ p: CGFloat) -> CGFloat {
        p < 0 ? lineWidth : lineWidth * (0.3 + 1.4 * p)
    }

    private func handlePoints() -> [CGPoint] {
        let r = selection
        return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY),
                CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)]
    }

    private func handleIndex(at p: CGPoint) -> Int? {
        handlePoints().firstIndex { hypot($0.x - p.x, $0.y - p.y) < 9 }
    }

    private func clamp(_ p: CGPoint, to r: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
    }

    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func beginSelection(at p: CGPoint) {
        annotations.removeAll()
        history.removeAll()
        current = nil
        phase = .selecting
        selection = CGRect(origin: p, size: .zero)
        drag = .selecting(p)
        setBarsHidden(true)
    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        switch phase {
        case .idle, .selecting:
            beginSelection(at: p)
        case .editing:
            commitText()
            if let h = handleIndex(at: p) {
                drag = .resizing(h)
            } else if tool == .move || !selection.contains(p) {
                if selection.contains(p) {
                    drag = .moving(CGPoint(x: p.x - selection.minX, y: p.y - selection.minY))
                } else {
                    beginSelection(at: p)
                }
            } else {
                beginDrawing(at: p, event: e)
            }
        }
        needsDisplay = true
    }

    private func beginDrawing(at p: CGPoint, event e: NSEvent) {
        switch tool {
        case .text:
            beginText(at: p)
        case .eraser:
            remember()
            erasedAny = false
            erase(at: p)
            drag = .drawing
        case .step:
            let n = annotations.filter { $0.tool == .step }.count + 1
            remember()
            annotations.append(Annotation(tool: .step, points: [p], color: color, width: lineWidth, number: n))
        case .move:
            break
        default:
            let w = penWidth(pressure(e))
            current = Annotation(tool: tool, points: [p], widths: [w], color: color, width: lineWidth)
            drag = .drawing
        }
    }

    override func mouseDragged(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        switch drag {
        case .selecting(let origin):
            selection = rect(from: origin, to: clamp(p, to: bounds))
        case .moving(let off):
            var r = selection
            r.origin = CGPoint(x: min(max(0, p.x - off.x), bounds.width - r.width),
                               y: min(max(0, p.y - off.y), bounds.height - r.height))
            let d = CGPoint(x: r.minX - selection.minX, y: r.minY - selection.minY)
            selection = r
            for i in annotations.indices { annotations[i].translate(by: d) }
        case .resizing(let h):
            selection = resized(h, clamp(p, to: bounds))
        case .drawing:
            if tool == .eraser { erase(at: clamp(p, to: selection)); break }
            guard var c = current else { break }
            let q = clamp(p, to: selection)
            if c.tool == .pen {
                c.points.append(q)
                c.widths.append(penWidth(pressure(e)))
            } else {
                var end = q
                if e.modifierFlags.contains(.shift) { end = constrained(from: c.start, to: q, tool: c.tool) }
                c.points = [c.start, end]
            }
            current = c
        case .none:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        switch drag {
        case .selecting:
            if selection.width < 4 || selection.height < 4 {
                phase = .idle
                selection = .zero
            } else {
                phase = .editing
                setBarsHidden(false)
                layoutBars()
            }
        case .moving, .resizing:
            layoutBars()
        case .drawing:
            if tool == .eraser && !erasedAny { _ = history.popLast() }   // nothing was erased: no undo step
            if let c = current {
                let moved = hypot(c.end.x - c.start.x, c.end.y - c.start.y)
                if c.tool == .pen || moved > 2 { remember(); annotations.append(c) }
            }
            current = nil
        case .none:
            break
        }
        drag = .none
        needsDisplay = true
    }

    private func constrained(from s: CGPoint, to e: CGPoint, tool: Tool) -> CGPoint {
        let dx = e.x - s.x, dy = e.y - s.y
        switch tool {
        case .rect, .blur:
            let m = max(abs(dx), abs(dy))
            return CGPoint(x: s.x + (dx < 0 ? -m : m), y: s.y + (dy < 0 ? -m : m))
        default:
            let angle = atan2(dy, dx), step = CGFloat.pi / 4
            let snapped = (angle / step).rounded() * step
            let len = hypot(dx, dy)
            return CGPoint(x: s.x + cos(snapped) * len, y: s.y + sin(snapped) * len)
        }
    }

    private func resized(_ h: Int, _ p: CGPoint) -> CGRect {
        var minX = selection.minX, maxX = selection.maxX
        var minY = selection.minY, maxY = selection.maxY
        switch h {
        case 0: minX = p.x; minY = p.y
        case 1: minY = p.y
        case 2: maxX = p.x; minY = p.y
        case 3: maxX = p.x
        case 4: maxX = p.x; maxY = p.y
        case 5: maxY = p.y
        case 6: minX = p.x; maxY = p.y
        default: minX = p.x
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }

    // MARK: - Eraser and undo history

    private func remember() {
        history.append(annotations)
        if history.count > 50 { history.removeFirst() }
    }

    private func erase(at p: CGPoint) {
        let radius = max(8, lineWidth * 3)
        let before = annotations.count
        annotations.removeAll { $0.hits(p, radius: radius) }
        if annotations.count != before { erasedAny = true; needsDisplay = true }
    }

    // MARK: - Text

    private func beginText(at p: CGPoint) {
        commitText()
        let size = max(14, lineWidth * 5 + 8)
        let f = NSTextField(frame: CGRect(x: p.x, y: p.y, width: max(120, selection.maxX - p.x), height: size + 8))
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: size, weight: .semibold)
        f.textColor = color
        f.placeholderString = L("Text…")
        f.delegate = self
        addSubview(f)
        window?.makeFirstResponder(f)
        textField = f
        textOrigin = p
    }

    private func commitText() {
        guard let f = textField else { return }
        let t = f.stringValue
        f.removeFromSuperview()
        textField = nil
        if !t.isEmpty {
            remember()
            annotations.append(Annotation(tool: .text, points: [textOrigin], color: color, width: lineWidth, text: t))
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) { commitText(); return true }
        if sel == #selector(NSResponder.cancelOperation(_:)) { textField?.stringValue = ""; commitText(); return true }
        return false
    }

    // MARK: - Keyboard

    override func keyDown(with e: NSEvent) {
        let key = e.charactersIgnoringModifiers ?? ""
        if e.keyCode == 53 { controller?.close(); return }                       // Esc
        if e.keyCode == 36 || e.keyCode == 76 { if phase == .editing { copyTapped() }; return } // Enter
        if e.modifierFlags.contains(.command) {
            switch key {
            case "z": undoTapped()
            case "c": copyTapped()
            case "s": saveTapped()
            default: super.keyDown(with: e)
            }
            return
        }
        super.keyDown(with: e)
    }

    // MARK: - Tool bars

    private func buildBars() {
        let defs: [(Tool, String, String)] = [
            (.move, "arrow.up.and.down.and.arrow.left.and.right", L("Move / resize")),
            (.pen, "pencil.tip", L("Pen")),
            (.line, "line.diagonal", L("Line")),
            (.arrow, "arrow.up.right", L("Arrow")),
            (.rect, "rectangle", L("Rectangle")),
            (.marker, "highlighter", L("Highlighter")),
            (.text, "textformat", L("Text")),
            (.step, "1.circle", L("Step number")),
            (.blur, "squareshape.split.3x3", L("Blur")),
            (.eraser, "eraser", L("Eraser"))
        ]
        var toolViews: [NSView] = []
        for d in defs {
            let b = IconButton(symbol: d.1, tip: d.2, target: self, action: #selector(toolTapped(_:)))
            b.tag = d.0.rawValue
            toolButtons[d.0] = b
            toolViews.append(b)
        }
        toolBar = HUDBar(vertical: true, items: toolViews)

        let actions: [NSView] = [
            IconButton(symbol: "arrow.uturn.backward", tip: L("Undo (⌘Z)"), target: self, action: #selector(undoTapped)),
            BarDivider(vertical: false),
            IconButton(symbol: "text.viewfinder", tip: L("Copy text (OCR)"), target: self, action: #selector(ocrTapped)),
            IconButton(symbol: "pin", tip: L("Pin to screen"), target: self, action: #selector(pinTapped)),
            IconButton(symbol: "square.and.arrow.down", tip: L("Save (⌘S)"), target: self, action: #selector(saveTapped)),
            IconButton(symbol: "doc.on.doc", tip: L("Copy to clipboard (⌘C / Enter)"), target: self, action: #selector(copyTapped)),
            BarDivider(vertical: false),
            IconButton(symbol: "xmark", tip: L("Close (Esc)"), target: self, action: #selector(closeTapped))
        ]
        actionBar = HUDBar(vertical: false, items: actions)

        var styleViews: [NSView] = []
        for c in palette {
            let s = SwatchButton(color: c, target: self, action: #selector(swatchTapped(_:)))
            swatches.append(s)
            styleViews.append(s)
        }
        swatches.first?.isOn = true
        styleViews.append(BarDivider(vertical: false))
        let slider = NSSlider(value: Double(lineWidth), minValue: 1, maxValue: 12, target: self, action: #selector(sliderChanged(_:)))
        slider.controlSize = .small
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 80).isActive = true
        slider.toolTip = L("Thickness")
        styleViews.append(slider)
        styleBar = HUDBar(vertical: false, items: styleViews)

        [toolBar, actionBar, styleBar].forEach { addSubview($0!) }
        setBarsHidden(true)
        refreshBars()
    }

    private func setBarsHidden(_ hidden: Bool) {
        toolBar.isHidden = hidden
        actionBar.isHidden = hidden
        styleBar.isHidden = hidden || tool == .move
    }

    private func refreshBars() {
        for (t, b) in toolButtons { b.isOn = (t == tool) }
        guard toolBar != nil else { return }
        styleBar.isHidden = (phase != .editing) || tool == .move
    }

    private func layoutBars() {
        guard phase == .editing else { return }
        let m: CGFloat = 8
        var tx = selection.maxX + m
        if tx + toolBar.frame.width > bounds.width - 4 { tx = selection.minX - m - toolBar.frame.width }
        if tx < 4 { tx = bounds.width - toolBar.frame.width - 12 }
        let ty = max(4, min(selection.minY, bounds.height - toolBar.frame.height - 4))
        toolBar.setFrameOrigin(CGPoint(x: tx, y: ty))

        var ay = selection.maxY + m
        var below = true
        if ay + actionBar.frame.height > bounds.height - 4 { ay = selection.minY - m - actionBar.frame.height; below = false }
        if ay < 4 { ay = selection.maxY - actionBar.frame.height - m; below = true }
        let ax = max(4, min(selection.maxX - actionBar.frame.width, bounds.width - actionBar.frame.width - 4))
        actionBar.setFrameOrigin(CGPoint(x: ax, y: ay))

        var sy = below ? ay + actionBar.frame.height + 6 : ay - styleBar.frame.height - 6
        sy = max(4, min(sy, bounds.height - styleBar.frame.height - 4))
        let sx = max(4, min(ax + actionBar.frame.width - styleBar.frame.width, bounds.width - styleBar.frame.width - 4))
        styleBar.setFrameOrigin(CGPoint(x: sx, y: sy))
    }

    @objc private func toolTapped(_ s: NSButton) {
        commitText()
        tool = Tool(rawValue: s.tag) ?? .move
        layoutBars()
    }

    @objc private func swatchTapped(_ s: SwatchButton) {
        color = s.swatch
        swatches.forEach { $0.isOn = ($0 === s) }
    }

    @objc private func sliderChanged(_ s: NSSlider) { lineWidth = CGFloat(s.doubleValue) }

    // MARK: - Actions

    @objc private func undoTapped() {
        if textField != nil { return }
        if let previous = history.popLast() { annotations = previous; needsDisplay = true }
    }

    @objc private func closeTapped() { controller?.close() }

    /// Renders the selected area, including annotations, at full pixel resolution.
    private func renderSelection() -> CGImage? {
        commitText()
        let w = Int((selection.width * scale).rounded()), h = Int((selection.height * scale).rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -selection.minX, y: -selection.minY)
        renderer.drawBackground(ctx)
        for a in annotations { renderer.draw(a, ctx) }
        return ctx.makeImage()
    }

    @objc private func copyTapped() {
        guard let cg = renderSelection() else { return }
        let img = NSImage(cgImage: cg, size: selection.size)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
        NSSound(named: "Tink")?.play()
        controller?.close()
    }

    @objc private func saveTapped() {
        guard let cg = renderSelection(),
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            NSSound.beep()
            return
        }
        do {
            _ = try Storage.savePNG(data)
        } catch {
            // Keep the overlay open so the capture is not lost.
            Alerts.error(L("Could not save the screenshot"), error.localizedDescription)
            return
        }
        NSSound(named: "Tink")?.play()
        controller?.close()
    }

    @objc private func pinTapped() {
        guard let cg = renderSelection(), let win = window else { return }
        let frame = CGRect(x: win.frame.minX + selection.minX,
                           y: win.frame.maxY - selection.maxY,
                           width: selection.width, height: selection.height)
        controller?.close()
        PinWindow.show(cg, frame: frame)
    }

    @objc private func ocrTapped() {
        guard let cg = renderSelection() else { return }
        controller?.close()
        let request = VNRecognizeTextRequest { req, _ in
            let lines = (req.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string } ?? []
            let text = lines.joined(separator: "\n")
            DispatchQueue.main.async {
                guard !text.isEmpty else { NSSound.beep(); return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                NSSound(named: "Tink")?.play()
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try VNImageRequestHandler(cgImage: cg).perform([request])
            } catch {
                DispatchQueue.main.async { NSSound.beep() }
            }
        }
    }
}
