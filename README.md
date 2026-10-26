<p align="center"><img src="Resources/AppIcon.png" width="128" alt="ZoomDNZ icon"></p>

# ZoomDNZ

**Capture, zoom and draw on your Mac screen, from the menu bar, fully offline.**

ZoomDNZ brings the two tools many people install separately into one small native app:
[Lightshot](https://app.prntscr.com/)-style area screenshots and [ZoomIt](https://learn.microsoft.com/sysinternals/downloads/zoomit)-style screen zoom and live annotation.
It is built for presenters, teachers, support engineers and anyone who explains things on screen.

- **Private by design.** No network code, no accounts, no cloud, no telemetry, no third-party dependencies. Screenshots stay in your Documents folder.
- **Native and light.** Swift + AppKit, SF Symbols, system-style HUD. Universal binary for Apple Silicon and Intel (macOS 14+).
- **Pen-ready.** Tablet pen pressure changes stroke width.
- **Speaks your language.** English, Türkçe and Deutsch, following the system language.

## What you can do

| Shortcut | Action |
|---|---|
| `⌃⌥A` | **Capture area**: select, move and resize, annotate (pen, line, arrow, rectangle, highlighter, text, numbered steps, blur), then copy, save, pin to screen, or copy text with on-device OCR |
| `⌃⌥Z` | **Still zoom**: freeze and magnify the screen, mouse pans, wheel zooms, click to pin the view and start drawing; right-click steps back to zoom |
| `⌃⌥D` | **Draw on screen**: colors, highlighter, shapes, whiteboard and blackboard modes, auto-hiding toolbar |

The full shortcut list is in the menu bar icon → **Shortcuts…**

## Requirements
- macOS 14+ and Xcode Command Line Tools (`xcode-select --install`)

## Build and run
```bash
./build.sh
open build/ZoomDNZ.app
```
On first run grant **Screen Recording** permission (System Settings › Privacy & Security), then restart the app.
Ad-hoc signing changes identity on every build, so macOS may ask again; set `SIGN_IDENTITY="<certificate name>"` to keep the permission across builds.

## Test
```bash
swift test
```
Tests use Swift Testing, which ships with the Command Line Tools (XCTest would require full Xcode).

## Where files go
Saved screenshots: `~/Documents/ZoomDNZ Screenshots/` (directory 0700, files 0600). Nothing is uploaded anywhere.

## Security and privacy
The app has no network code and no secrets. Captures can contain sensitive data, so they are stored owner-only and never logged.


## License
MIT, see [LICENSE](LICENSE).
