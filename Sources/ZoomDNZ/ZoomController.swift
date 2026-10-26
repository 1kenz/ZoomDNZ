import AppKit

@MainActor
final class ZoomController {
    static var active: ZoomController?
    private var window: ZoomWindow?

    static func begin(_ mode: ZoomView.Mode) {
        guard active == nil, CaptureController.active == nil else { return }
        guard Permissions.ensureScreenRecording() else { return }
        let c = ZoomController()
        active = c
        Task { @MainActor in await c.start(mode) }
    }

    private func start(_ mode: ZoomView.Mode) async {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let img = try? await Capture.snapshot(displayID: CGDirectDisplayID(num.uint32Value),
                                                    scale: screen.backingScaleFactor) else {
            ZoomController.active = nil
            Permissions.showDenied()
            return
        }
        let start = CGPoint(x: mouse.x - screen.frame.minX, y: screen.frame.maxY - mouse.y)
        let w = ZoomWindow(screen: screen, image: img, mode: mode, mouse: start, controller: self)
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.orderFrontRegardless()
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(w.contentView)
    }

    func close() {
        (window?.contentView as? ZoomView)?.setCursorHidden(false)
        window?.orderOut(nil)
        window = nil
        ZoomController.active = nil
    }
}

final class ZoomWindow: NSWindow {
    init(screen: NSScreen, image: CGImage, mode: ZoomView.Mode, mouse: CGPoint, controller: ZoomController) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let v = ZoomView(frame: CGRect(origin: .zero, size: screen.frame.size), image: image, mode: mode, mouse: mouse)
        v.controller = controller
        contentView = v
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
