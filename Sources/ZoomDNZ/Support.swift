import AppKit
import ScreenCaptureKit

/// Localized string (key = English text; Turkish and German live in the .lproj files).
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

enum Storage {
    /// ~/Documents/ZoomDNZ Screenshots (kept apart from the project folder name). Owner-only access.
    static func capturesDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = documents.appendingPathComponent("ZoomDNZ Screenshots", isDirectory: true)
        // A failure here is not swallowed silently: savePNG will throw when the write fails.
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir
    }

    /// Writes PNG data to a new, unique, owner-only (0600) file. Never overwrites an existing capture.
    static func savePNG(_ data: Data, in directory: URL = capturesDirectory()) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = "ZoomDNZ \(formatter.string(from: Date()))"
        var url = directory.appendingPathComponent("\(base).png")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base) (\(counter)).png")
            counter += 1
        }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }
}

enum Alerts {
    /// Modal alert shown above full-screen overlays (which use the screen-saver window level).
    @MainActor
    static func error(_ title: String, _ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: L("OK"))
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        alert.runModal()
    }
}

enum Permissions {
    @MainActor
    static func ensureScreenRecording() -> Bool {
        // The preflight check returns false negatives on some macOS versions, so we attempt the real
        // capture and show the alert only if that fails.
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        return true
    }

    @MainActor
    static func showDenied() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Screen Recording permission required")
        alert.informativeText = L("System Settings › Privacy & Security › Screen & System Audio Recording: enable ZoomDNZ, then restart the app.")
        alert.addButton(withTitle: L("Open System Settings"))
        alert.addButton(withTitle: L("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { openSettings() }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum CaptureError: Error { case displayNotFound }

enum Capture {
    /// Full-resolution (Retina included) snapshot of one display.
    static func snapshot(displayID: CGDirectDisplayID, scale: CGFloat) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.width = Int(CGFloat(display.width) * scale)
        cfg.height = Int(CGFloat(display.height) * scale)
        cfg.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }
}
