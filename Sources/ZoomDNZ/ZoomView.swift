import AppKit

/// ZoomIt-style: magnifies a frozen screenshot and draws on top of it.
final class ZoomView: NSView, NSTextFieldDelegate {
    enum Mode { case zoom, draw }
    enum Board { case none, white, black }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    weak var controller: ZoomController?
    let image: CGImage
    let renderer: SceneRenderer
    let scale: CGFloat
    let startedInZoom: Bool

    var mode: Mode
    var zoom: CGFloat
    var origin = CGPoint.zero          // top-left of the visible region, in image space
    var mouse: CGPoint                 // view coordinates
    var board: Board = .none
    var annotations: [Annotation] = []
    var current: Annotation?
    private var history: [[Annotation]] = []   // snapshots for undo (draw, erase, clear)
    private var erasedAny = false
    private var erasing = false               // an erase gesture is in progress
    var tool: Tool = .pen { didSet { refreshBar() } }
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 4

    private var tabHeld = false
    private var badgeText = ""
    private var badgeUntil = Date.distantPast
    private var barPinnedUntil = Date.distantPast
    private var cursorHidden = false
    private var bar: HUDBar!
    private var toolButtons: [Tool: IconButton] = [:]
    private var swatches: [SwatchButton] = []
    private var textField: NSTextField?
    private var textOrigin = CGPoint.zero

    private let colors: [(NSColor, String)] = [
        (.systemRed, L("Red (R)")), (.systemGreen, L("Green (G)")), (.systemBlue, L("Blue (B)")),
        (.systemOrange, L("Orange (O)")), (.systemYellow, L("Yellow (Y)")), (.systemPink, L("Pink (P)"))
    ]

    init(frame: NSRect, image: CGImage, mode: Mode, mouse: CGPoint) {
        self.image = image
        self.renderer = SceneRenderer(image: image, bounds: CGRect(origin: .zero, size: frame.size))
        self.scale = CGFloat(image.width) / max(1, frame.width)
        self.mode = mode
        self.startedInZoom = (mode == .zoom)
        self.zoom = (mode == .zoom) ? 2 : 1
        self.mouse = mouse
        super.init(frame: frame)
        updateOrigin()
        buildBar()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        if mode == .draw { pinBar() }
        updateBar()
        if mode == .zoom { showBadge(String(format: "%.1f×", zoom)) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) yok") }

    // MARK: - Coordinates

    private func updateOrigin() {
        let f = 1 - 1 / zoom
        origin = CGPoint(x: mouse.x * f, y: mouse.y * f)
    }

    private func toImage(_ v: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + v.x / zoom, y: origin.y + v.y / zoom)
    }

    // MARK: - Drawing

    private func drawScene(_ ctx: CGContext) {
        ctx.saveGState()
        ctx.scaleBy(x: zoom, y: zoom)
        ctx.translateBy(x: -origin.x, y: -origin.y)
        ctx.interpolationQuality = .high
        switch board {
        case .none: renderer.drawBackground(ctx)
        case .white: ctx.setFillColor(NSColor.white.cgColor); ctx.fill(renderer.bounds)
        case .black: ctx.setFillColor(NSColor(white: 0.07, alpha: 1).cgColor); ctx.fill(renderer.bounds)
        }
        for a in annotations { renderer.draw(a, ctx) }
        if let c = current { renderer.draw(c, ctx) }
        ctx.restoreGState()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        drawScene(ctx)

        if mode == .draw && cursorHidden {
            let r = tool == .eraser ? eraserRadius * zoom : max(4, lineWidth * zoom / 2)
            let rect = CGRect(x: mouse.x - r, y: mouse.y - r, width: 2 * r, height: 2 * r)
            let outer = NSBezierPath(ovalIn: rect.insetBy(dx: -1.5, dy: -1.5))
            outer.lineWidth = 1
            NSColor.black.withAlphaComponent(0.5).setStroke(); outer.stroke()
            let ring = NSBezierPath(ovalIn: rect)
            ring.lineWidth = 1.5
            color.setStroke(); ring.stroke()
        }

        if Date() < badgeUntil {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let s = badgeText as NSString
            let size = s.size(withAttributes: attrs)
            let pill = CGRect(x: bounds.width - size.width - 44, y: 24, width: size.width + 24, height: size.height + 10)
            NSColor.black.withAlphaComponent(0.65).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 10, yRadius: 10).fill()
            s.draw(at: CGPoint(x: pill.minX + 12, y: pill.minY + 5), withAttributes: attrs)
        }
    }

    // MARK: - Eraser and undo history

    private var eraserRadius: CGFloat { max(8, lineWidth * 3) / zoom }

    private func remember() {
        history.append(annotations)
        if history.count > 50 { history.removeFirst() }
    }

    private func erase(at p: CGPoint) {
        let radius = eraserRadius
        let before = annotations.count
        annotations.removeAll { $0.hits(p, radius: radius) }
        if annotations.count != before { erasedAny = true; needsDisplay = true }
    }

    private func clearAll() {
        guard !annotations.isEmpty else { return }
        remember()
        annotations.removeAll()
        needsDisplay = true
    }

    private func showBadge(_ text: String) {
        badgeText = text
        badgeUntil = Date().addingTimeInterval(1.5)
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.needsDisplay = true }
    }

    // MARK: - Mouse / pen

    private func pressure(_ e: NSEvent) -> CGFloat {
        e.subtype == .tabletPoint ? max(0.05, CGFloat(e.pressure)) : -1
    }

    private func penWidth(_ p: CGFloat) -> CGFloat {
        p < 0 ? lineWidth : lineWidth * (0.3 + 1.4 * p)
    }

    /// Like ZoomIt: Shift = line, ⌘ = rectangle, ⌘+Shift = arrow, Tab held = ellipse.
    private func effectiveTool(_ e: NSEvent) -> Tool {
        if tool == .text || tool == .eraser { return tool }
        let f = e.modifierFlags
        if f.contains(.command) && f.contains(.shift) { return .arrow }
        if f.contains(.command) { return .rect }
        if f.contains(.shift) { return .line }
        if tabHeld { return .ellipse }
        return tool
    }

    private func enterDraw() {
        mode = .draw
        pinBar()
        updateBar()
    }

    override func mouseMoved(with e: NSEvent) {
        mouse = convert(e.locationInWindow, from: nil)
        if mode == .zoom { updateOrigin() }
        updateBar()
        needsDisplay = true
    }

    override func mouseDown(with e: NSEvent) {
        mouse = convert(e.locationInWindow, from: nil)
        commitText()
        if mode == .zoom {
            // The click that pins the zoom must not also start a stroke.
            enterDraw()
            needsDisplay = true
            return
        }
        let t = effectiveTool(e)
        let ip = toImage(mouse)
        if t == .eraser {
            remember()
            erasing = true
            erasedAny = false
            erase(at: ip)
        } else if t == .text {
            beginText(atView: mouse, image: ip)
        } else {
            current = Annotation(tool: t, points: [ip], widths: [penWidth(pressure(e))], color: color, width: lineWidth)
        }
        needsDisplay = true
    }

    override func mouseDragged(with e: NSEvent) {
        mouse = convert(e.locationInWindow, from: nil)
        if erasing {
            erase(at: toImage(mouse))
            updateBar()
            needsDisplay = true
            return
        }
        if var c = current {
            let q = toImage(mouse)
            if c.tool == .pen || c.tool == .freeMarker {
                c.points.append(q)
                c.widths.append(penWidth(pressure(e)))
            } else {
                c.points = [c.start, q]
            }
            current = c
        }
        updateBar()
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        if erasing {
            erasing = false
            if !erasedAny { _ = history.popLast() }   // nothing was erased: no undo step
        }
        if let c = current {
            let moved = hypot(c.end.x - c.start.x, c.end.y - c.start.y)
            if c.tool == .pen || c.tool == .freeMarker || moved > 2 { remember(); annotations.append(c) }
        }
        current = nil
        needsDisplay = true
    }

    override func rightMouseDown(with e: NSEvent) {
        commitText()
        if mode == .draw && startedInZoom {
            mode = .zoom
            current = nil
            updateOrigin()
            updateBar()
            needsDisplay = true
        } else {
            controller?.close()
        }
    }

    override func scrollWheel(with e: NSEvent) {
        let d = e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 0.01 : 0.1)
        if mode == .zoom {
            changeZoom(1 + d)
        } else {
            lineWidth = min(24, max(1, lineWidth + d * 10))
            showBadge(String(format: L("Thickness %d"), Int(lineWidth.rounded())))
        }
    }

    private func changeZoom(_ factor: CGFloat) {
        zoom = min(8, max(1.25, zoom * factor))
        updateOrigin()
        showBadge(String(format: "%.1f×", zoom))
        needsDisplay = true
    }

    // MARK: - Keyboard

    override func keyDown(with e: NSEvent) {
        let key = (e.charactersIgnoringModifiers ?? "").lowercased()
        if e.keyCode == 53 { controller?.close(); return }                  // Esc
        if e.keyCode == 48 { tabHeld = true; return }                       // Tab
        if e.modifierFlags.contains(.command) || e.modifierFlags.contains(.control) {
            switch key {
            case "z": undoTapped()
            case "c": copyTapped()
            case "s": saveTapped()
            default: break
            }
            return
        }
        if mode == .zoom {
            if e.keyCode == 126 { changeZoom(1.25) }
            if e.keyCode == 125 { changeZoom(0.8) }
            return
        }
        switch key {
        case "r": setColor(0)
        case "g": setColor(1)
        case "b": setColor(2)
        case "o": setColor(3)
        case "y": setColor(4)
        case "p": setColor(5)
        case "h": tool = .freeMarker
        case "t": tool = .text
        case "w": toggleBoard(.white)
        case "k": toggleBoard(.black)
        case "e": clearAll()
        case "x": tool = .eraser
        default: break
        }
    }

    override func keyUp(with e: NSEvent) {
        if e.keyCode == 48 { tabHeld = false }
    }

    // MARK: - Text

    private func beginText(atView p: CGPoint, image ip: CGPoint) {
        let size = max(14, lineWidth * 5 + 8) * zoom
        let f = NSTextField(frame: CGRect(x: p.x, y: p.y, width: max(160, bounds.width - p.x - 20), height: size + 10))
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
        textOrigin = ip
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

    // MARK: - Tool bar (appears near the bottom edge)

    private func buildBar() {
        let defs: [(Tool, String, String)] = [
            (.pen, "pencil.tip", L("Pen")),
            (.freeMarker, "highlighter", L("Highlighter (H)")),
            (.line, "line.diagonal", L("Line (draw while holding Shift)")),
            (.arrow, "arrow.up.right", L("Arrow (draw while holding ⌘+Shift)")),
            (.rect, "rectangle", L("Rectangle (draw while holding ⌘)")),
            (.ellipse, "circle", L("Ellipse (draw while holding Tab)")),
            (.text, "textformat", L("Text (T)")),
            (.eraser, "eraser", L("Eraser (X)"))
        ]
        var views: [NSView] = []
        for d in defs {
            let b = IconButton(symbol: d.1, tip: d.2, target: self, action: #selector(toolTapped(_:)))
            b.tag = d.0.rawValue
            toolButtons[d.0] = b
            views.append(b)
        }
        views.append(BarDivider(vertical: false))
        for (c, name) in colors {
            let s = SwatchButton(color: c, target: self, action: #selector(swatchTapped(_:)))
            s.toolTip = name
            swatches.append(s)
            views.append(s)
        }
        swatches.first?.isOn = true
        views.append(BarDivider(vertical: false))
        views += [
            IconButton(symbol: "arrow.uturn.backward", tip: L("Undo (⌘Z)"), target: self, action: #selector(undoTapped)),
            IconButton(symbol: "square", tip: L("Whiteboard (W)"), target: self, action: #selector(whiteTapped)),
            IconButton(symbol: "square.fill", tip: L("Blackboard (K)"), target: self, action: #selector(blackTapped)),
            IconButton(symbol: "trash", tip: L("Clear all (E)"), target: self, action: #selector(clearTapped)),
            BarDivider(vertical: false),
            IconButton(symbol: "doc.on.doc", tip: L("Copy to clipboard (⌘C)"), target: self, action: #selector(copyTapped)),
            IconButton(symbol: "square.and.arrow.down", tip: L("Save (⌘S)"), target: self, action: #selector(saveTapped)),
            IconButton(symbol: "xmark", tip: L("Close (Esc)"), target: self, action: #selector(closeTapped))
        ]
        bar = HUDBar(vertical: false, items: views)
        bar.setFrameOrigin(CGPoint(x: (bounds.width - bar.frame.width) / 2, y: bounds.height - bar.frame.height - 20))
        addSubview(bar)
        refreshBar()
    }

    private func pinBar() {
        barPinnedUntil = Date().addingTimeInterval(3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.1) { [weak self] in self?.updateBar() }
    }

    private func updateBar() {
        guard bar != nil else { return }
        let overBar = bar.frame.insetBy(dx: -6, dy: -6).contains(mouse)
        let near = mouse.y > bounds.height - bar.frame.height - 70 || Date() < barPinnedUntil
        bar.isHidden = !(mode == .draw && near)
        setCursorHidden(mode == .draw && !(overBar && !bar.isHidden))
    }

    func setCursorHidden(_ hidden: Bool) {
        guard hidden != cursorHidden else { return }
        cursorHidden = hidden
        if hidden { NSCursor.hide() } else { NSCursor.unhide() }
    }

    private func refreshBar() {
        for (t, b) in toolButtons { b.isOn = (t == tool) }
    }

    private func setColor(_ i: Int) {
        color = colors[i].0
        for (n, s) in swatches.enumerated() { s.isOn = (n == i) }
        needsDisplay = true
    }

    private func toggleBoard(_ b: Board) {
        board = (board == b) ? .none : b
        needsDisplay = true
    }

    @objc private func toolTapped(_ s: NSButton) { commitText(); tool = Tool(rawValue: s.tag) ?? .pen }
    @objc private func swatchTapped(_ s: SwatchButton) {
        if let i = swatches.firstIndex(where: { $0 === s }) { setColor(i) }
    }
    @objc private func undoTapped() {
        if textField != nil { return }
        if let previous = history.popLast() { annotations = previous; needsDisplay = true }
    }
    @objc private func whiteTapped() { toggleBoard(.white) }
    @objc private func blackTapped() { toggleBoard(.black) }
    @objc private func clearTapped() { clearAll() }
    @objc private func closeTapped() { controller?.close() }

    // MARK: - Export

    private func renderCurrent() -> CGImage? {
        commitText()
        let w = Int((bounds.width * scale).rounded()), h = Int((bounds.height * scale).rounded())
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        drawScene(ctx)
        return ctx.makeImage()
    }

    @objc private func copyTapped() {
        guard let cg = renderCurrent() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: cg, size: bounds.size)])
        NSSound(named: "Tink")?.play()
        showBadge(L("Copied to clipboard"))
    }

    @objc private func saveTapped() {
        guard let cg = renderCurrent(),
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            NSSound.beep()
            return
        }
        do {
            _ = try Storage.savePNG(data)
        } catch {
            Alerts.error(L("Could not save the screenshot"), error.localizedDescription)
            return
        }
        NSSound(named: "Tink")?.play()
        showBadge(L("Saved"))
    }
}
