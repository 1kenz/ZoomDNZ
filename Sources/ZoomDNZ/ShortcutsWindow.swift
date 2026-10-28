import SwiftUI
import AppKit

private struct ShortcutItem: Identifiable {
    let id = UUID()
    let keys: [String]
    let title: String
}

private struct ShortcutSection: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let items: [ShortcutItem]
}

private let sections: [ShortcutSection] = [
    ShortcutSection(title: L("General"), symbol: "command", items: [
        ShortcutItem(keys: ["⌃", "⌥", "A"], title: L("Capture area")),
        ShortcutItem(keys: ["⌃", "⌥", "Z"], title: L("Zoom (still screen)")),
        ShortcutItem(keys: ["⌃", "⌥", "D"], title: L("Draw on screen")),
        ShortcutItem(keys: ["Esc"], title: L("Exit / close"))
    ]),
    ShortcutSection(title: L("Area Capture"), symbol: "camera.viewfinder", items: [
        ShortcutItem(keys: [L("Drag")], title: L("Select an area, then move it or resize from the corners")),
        ShortcutItem(keys: ["Enter"], title: L("Copy to clipboard and close")),
        ShortcutItem(keys: ["⌘", "C"], title: L("Copy to clipboard")),
        ShortcutItem(keys: ["⌘", "S"], title: L("Save to Documents/ZoomDNZ Screenshots")),
        ShortcutItem(keys: ["⌘", "Z"], title: L("Undo last drawing")),
        ShortcutItem(keys: ["Shift", L("Drag")], title: L("Line/arrow in 45° steps, rectangle as square"))
    ]),
    ShortcutSection(title: "Zoom", symbol: "plus.magnifyingglass", items: [
        ShortcutItem(keys: [L("Mouse")], title: L("Pan the magnified view")),
        ShortcutItem(keys: [L("Scroll wheel")], title: L("Zoom in / out")),
        ShortcutItem(keys: ["↑", "↓"], title: L("Zoom in / out")),
        ShortcutItem(keys: ["+", "-"], title: L("Pen thickness")),
        ShortcutItem(keys: [L("Left click")], title: L("Switch to draw mode")),
        ShortcutItem(keys: [L("Right click")], title: L("Exit zoom"))
    ]),
    ShortcutSection(title: L("Drawing"), symbol: "pencil.tip", items: [
        ShortcutItem(keys: ["R", "G", "B", "O", "Y", "P"], title: L("Red, green, blue, orange, yellow, pink")),
        ShortcutItem(keys: ["H"], title: L("Highlighter")),
        ShortcutItem(keys: ["T"], title: L("Add text (finish with Enter)")),
        ShortcutItem(keys: ["N"], title: L("Numbered step: click to place 1, 2, 3…")),
        ShortcutItem(keys: ["X"], title: L("Eraser: drag over a drawing to remove it")),
        ShortcutItem(keys: ["Shift", L("Drag")], title: L("Straight line")),
        ShortcutItem(keys: ["⌘", L("Drag")], title: L("Rectangle")),
        ShortcutItem(keys: ["⌘", "Shift", L("Drag")], title: L("Arrow")),
        ShortcutItem(keys: ["Tab", L("Drag")], title: L("Ellipse (hold Tab)")),
        ShortcutItem(keys: [L("Scroll wheel")], title: L("Pen thickness")),
        ShortcutItem(keys: ["+", "-"], title: L("Pen thickness")),
        ShortcutItem(keys: ["W"], title: L("Toggle whiteboard")),
        ShortcutItem(keys: ["K"], title: L("Toggle blackboard")),
        ShortcutItem(keys: ["E"], title: L("Clear all drawings")),
        ShortcutItem(keys: ["⌘", "Z"], title: L("Undo")),
        ShortcutItem(keys: ["⌘", "C"], title: L("Copy screen to clipboard")),
        ShortcutItem(keys: ["⌘", "S"], title: L("Save screen to file")),
        ShortcutItem(keys: [L("Right click")], title: L("Back to zoom or exit"))
    ])
]

private struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(.callout, design: .rounded).weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .frame(minWidth: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.35), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.10), radius: 0, y: 1)
    }
}

private struct ShortcutRow: View {
    let item: ShortcutItem

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(item.title)
            Spacer(minLength: 12)
            keyCaps
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var keyCaps: some View {
        HStack(spacing: 4) {
            ForEach(0..<item.keys.count, id: \.self) { i in
                KeyCap(text: item.keys[i])
            }
        }
    }
}

private struct SectionCard: View {
    let section: ShortcutSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(section.title, systemImage: section.symbol)
                .font(.headline)
            rows
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(0..<section.items.count, id: \.self) { i in
                VStack(spacing: 0) {
                    ShortcutRow(item: section.items[i])
                    if i < section.items.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
    }
}

private struct ShortcutsHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "viewfinder")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("ZoomDNZ Shortcuts")).font(.title2.weight(.semibold))
                Text(L("You can always open this from the menu bar icon."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ShortcutsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ShortcutsHeader()
                ForEach(sections) { section in
                    SectionCard(section: section)
                }
            }
            .padding(24)
        }
        .frame(width: 540, height: 600)
    }
}

@MainActor
enum ShortcutsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: ShortcutsView()))
            w.title = L("ZoomDNZ Shortcuts")
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
