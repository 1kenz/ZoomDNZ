import AppKit

/// Apple-style translucent (vibrancy) bar.
final class HUDBar: NSVisualEffectView {
    init(vertical: Bool, items: [NSView]) {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        let stack = NSStackView(views: items)
        stack.orientation = vertical ? .vertical : .horizontal
        stack.alignment = vertical ? .centerX : .centerY
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        addSubview(stack)
        stack.layoutSubtreeIfNeeded()
        setFrameSize(stack.fittingSize)
        stack.frame = bounds
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) yok") }
}

/// Button with an SF Symbol that fills with the system accent color when selected.
final class IconButton: NSButton {
    var isOn = false { didSet { updateStyle() } }

    convenience init(symbol: String, tip: String, target: AnyObject?, action: Selector) {
        self.init(frame: .zero)
        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?.withSymbolConfiguration(cfg)
        imagePosition = .imageOnly
        isBordered = false
        title = ""
        toolTip = tip
        self.target = target
        self.action = action
        contentTintColor = .white
        wantsLayer = true
        layer?.cornerRadius = 8
        setAccessibilityLabel(tip)
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 30, height: 30) }

    private func updateStyle() {
        layer?.backgroundColor = isOn ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
    }
}

final class SwatchButton: NSButton {
    var swatch: NSColor = .red
    var isOn = false { didSet { needsDisplay = true } }

    convenience init(color: NSColor, target: AnyObject?, action: Selector) {
        self.init(frame: .zero)
        swatch = color
        isBordered = false
        title = ""
        self.target = target
        self.action = action
        setAccessibilityLabel(L("Color"))
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 26, height: 30) }

    override func draw(_ dirtyRect: NSRect) {
        let c = NSRect(x: (bounds.width - 16) / 2, y: (bounds.height - 16) / 2, width: 16, height: 16)
        swatch.setFill()
        NSBezierPath(ovalIn: c).fill()
        NSColor.white.withAlphaComponent(0.35).setStroke()
        let edge = NSBezierPath(ovalIn: c); edge.lineWidth = 0.5; edge.stroke()
        if isOn {
            NSColor.white.setStroke()
            let ring = NSBezierPath(ovalIn: c.insetBy(dx: -3, dy: -3))
            ring.lineWidth = 1.5
            ring.stroke()
        }
    }
}

final class BarDivider: NSView {
    private let vertical: Bool
    init(vertical: Bool) {
        self.vertical = vertical
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
    }
    required init?(coder: NSCoder) { fatalError() }
    // Horizontal rule in a vertical bar, vertical rule in a horizontal bar.
    override var intrinsicContentSize: NSSize {
        vertical ? NSSize(width: 20, height: 1) : NSSize(width: 1, height: 20)
    }
}

/// Floating pinned-image window.
final class PinWindow: NSPanel {
    private static var all: [PinWindow] = []

    static func show(_ image: CGImage, frame: CGRect) {
        let w = PinWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        w.level = .floating
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let v = PinView(frame: CGRect(origin: .zero, size: frame.size))
        v.image = NSImage(cgImage: image, size: frame.size)
        w.contentView = v
        all.append(w)
        w.orderFrontRegardless()
    }

    func dismiss() {
        orderOut(nil)
        PinWindow.all.removeAll { $0 === self }
    }

    override var canBecomeKey: Bool { true }
}

final class PinView: NSView {
    var image: NSImage?

    override func draw(_ dirtyRect: NSRect) {
        image?.draw(in: bounds)
        NSColor.white.withAlphaComponent(0.6).setStroke()
        let p = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)); p.lineWidth = 1; p.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { (window as? PinWindow)?.dismiss(); return }
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let w = window else { return }
        w.alphaValue = min(1, max(0.15, w.alphaValue + event.scrollingDeltaY * 0.01))
    }

    override func rightMouseDown(with event: NSEvent) { (window as? PinWindow)?.dismiss() }
}
