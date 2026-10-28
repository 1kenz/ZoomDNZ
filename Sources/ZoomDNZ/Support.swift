import AppKit
import ScreenCaptureKit

/// Localized string (key = English text; Turkish and German live in the .lproj files).
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

enum Storage {
    /// ~/Documents/ZoomDNZ Screenshots (kept apart from the project folder name). Path only, no side effects.
    static func capturesDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("ZoomDNZ Screenshots", isDirectory: true)
    }

    /// Creates the captures directory if needed and enforces owner-only access (0700) on every call,
    /// including when the directory already existed with looser permissions. Throws on failure.
    static func preparedCapturesDirectory() throws -> URL {
        let dir = capturesDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir
    }

    /// Writes PNG data to a new, unique, owner-only (0600) file. Never overwrites an existing capture.
    /// Without an explicit `directory` the prepared captures directory is used.
    static func savePNG(_ data: Data, in directory: URL? = nil) throws -> URL {
        let directory = try directory ?? preparedCapturesDirectory()
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
    /// Set once the system permission dialog has been shown in this launch.
    @MainActor private static var requestedThisLaunch = false

    /// Returns whether the caller should go on and capture.
    /// Without permission the first call shows only the macOS dialog (which has its own
    /// "Open System Settings" button) and stops, so the user never sees two dialogs for one action.
    /// Later calls try the real capture, because the preflight check returns false negatives on some
    /// macOS versions; `showDenied()` only opens System Settings if that capture fails again.
    @MainActor
    static func ensureScreenRecording() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        if !requestedThisLaunch {
            requestedThisLaunch = true
            CGRequestScreenCaptureAccess()
            return false
        }
        return true
    }

    /// Called when a capture fails. The macOS dialog already explains the permission, so no
    /// second dialog of our own: the first failure stays silent, later ones open System Settings.
    @MainActor private static var deniedOnce = false

    @MainActor
    static func showDenied() {
        if !deniedOnce { deniedOnce = true; return }
        openSettings()
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
