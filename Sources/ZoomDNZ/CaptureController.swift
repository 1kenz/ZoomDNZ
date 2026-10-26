import AppKit

@MainActor
final class CaptureController {
    static var active: CaptureController?
    private var windows: [OverlayWindow] = []

    static func begin() {
        guard active == nil else { return }
        guard Permissions.ensureScreenRecording() else { return }
        let c = CaptureController()
        active = c
        Task { @MainActor in await c.start() }
    }

    private func start() async {
        var shots: [(NSScreen, CGImage)] = []
        for s in NSScreen.screens {
            guard let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            if let img = try? await Capture.snapshot(displayID: CGDirectDisplayID(num.uint32Value),
                                                     scale: s.backingScaleFactor) {
                shots.append((s, img))
            }
        }
        guard !shots.isEmpty else {
            CaptureController.active = nil
            Permissions.showDenied()
            return
        }
        for (s, img) in shots {
            windows.append(OverlayWindow(screen: s, image: img, controller: self))
        }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        let key = windows.first { $0.frame.contains(mouse) } ?? windows[0]
        windows.forEach { $0.orderFrontRegardless() }
        key.makeKeyAndOrderFront(nil)
        key.makeFirstResponder(key.contentView)
    }

    func close() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        CaptureController.active = nil
    }
}

final class OverlayWindow: NSWindow {
    init(screen: NSScreen, image: CGImage, controller: CaptureController) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let v = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size), image: image)
        v.controller = controller
        contentView = v
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
