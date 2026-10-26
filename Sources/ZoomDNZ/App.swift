import AppKit
import Carbon.HIToolbox

@main
struct ZoomDNZApp {
    @MainActor static func main() {
        #if DEBUG
        if CommandLine.arguments.contains("--self-test") { exit(SelfTest.run()) }
        #endif

        // Single instance: quit silently if another copy is already running.
        let bundleID = Bundle.main.bundleIdentifier ?? "com.dnz.ZoomDNZ"
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }
        if !others.isEmpty { exit(0) }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

private struct HotKeySpec {
    let keyCode: Int
    let label: String
    let action: @MainActor () -> Void
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "ZoomDNZ")
        icon?.isTemplate = true
        statusItem.button?.image = icon

        let menu = NSMenu()
        let capture = NSMenuItem(title: L("Capture Area"), action: #selector(captureArea), keyEquivalent: "a")
        capture.keyEquivalentModifierMask = [.control, .option]
        capture.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)
        menu.addItem(capture)
        let zoom = NSMenuItem(title: L("Zoom (Still)"), action: #selector(startZoom), keyEquivalent: "z")
        zoom.keyEquivalentModifierMask = [.control, .option]
        zoom.image = NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: nil)
        menu.addItem(zoom)
        let draw = NSMenuItem(title: L("Draw on Screen"), action: #selector(startDraw), keyEquivalent: "d")
        draw.keyEquivalentModifierMask = [.control, .option]
        draw.image = NSImage(systemSymbolName: "pencil.tip.crop.circle", accessibilityDescription: nil)
        menu.addItem(draw)
        menu.addItem(.separator())

        let folder = NSMenuItem(title: L("Open Captures Folder"), action: #selector(openFolder), keyEquivalent: "")
        folder.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(folder)
        let keys = NSMenuItem(title: L("Shortcuts…"), action: #selector(showShortcuts), keyEquivalent: "")
        keys.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        menu.addItem(keys)
        let perm = NSMenuItem(title: L("Screen Recording Permission…"), action: #selector(openPermission), keyEquivalent: "")
        perm.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)
        menu.addItem(perm)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Quit ZoomDNZ"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        // Show the shortcut list once on first launch.
        if !UserDefaults.standard.bool(forKey: "shortcutsShown") {
            UserDefaults.standard.set(true, forKey: "shortcutsShown")
            ShortcutsWindow.show()
        }

        var unavailable: [String] = []
        for spec in hotKeySpecs {
            let registered = HotKey.register(keyCode: UInt32(spec.keyCode),
                                             modifiers: UInt32(controlKey | optionKey),
                                             handler: spec.action)
            if !registered { unavailable.append(spec.label) }
        }
        if !unavailable.isEmpty {
            Alerts.error(L("Shortcut unavailable"),
                         String(format: L("These shortcuts are already used by another app: %@"),
                                unavailable.joined(separator: ", ")))
        }
    }

    private let hotKeySpecs: [HotKeySpec] = [
        HotKeySpec(keyCode: kVK_ANSI_A, label: "⌃⌥A", action: { CaptureController.begin() }),
        HotKeySpec(keyCode: kVK_ANSI_Z, label: "⌃⌥Z", action: { ZoomController.begin(.zoom) }),
        HotKeySpec(keyCode: kVK_ANSI_D, label: "⌃⌥D", action: { ZoomController.begin(.draw) })
    ]

    @objc private func startZoom() { ZoomController.begin(.zoom) }
    @objc private func startDraw() { ZoomController.begin(.draw) }

    @objc private func captureArea() { CaptureController.begin() }

    @objc private func openFolder() {
        do {
            NSWorkspace.shared.open(try Storage.preparedCapturesDirectory())
        } catch {
            Alerts.error(L("Could not open the captures folder"), error.localizedDescription)
        }
    }

    @objc private func showShortcuts() { ShortcutsWindow.show() }

    @objc private func openPermission() { Permissions.openSettings() }
}
