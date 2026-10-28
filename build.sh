#!/bin/bash
# ZoomDNZ: build a universal (arm64 + x86_64) .app bundle
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/ZoomDNZ"
[ -f "$BIN" ] || { echo "Built binary not found: $BIN"; exit 1; }

APP="build/ZoomDNZ.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ZoomDNZ"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/en.lproj Resources/tr.lproj Resources/de.lproj "$APP/Contents/Resources/"

# DNZ About metadata (core/standards/about-standard.md §3): build facts come from the build, never from source.
# Release builds: DNZ_CHANNEL=stable DNZ_ENVIRONMENT=production ./build.sh
PLB=/usr/libexec/PlistBuddy; PL="$APP/Contents/Info.plist"
set_plist() { "$PLB" -c "Set :$1 $2" "$PL" 2>/dev/null || "$PLB" -c "Add :$1 string $2" "$PL"; }
set_plist DNZCommit      "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
set_plist DNZReleaseDate "$(date -u +%Y-%m-%d)"
set_plist DNZChannel     "${DNZ_CHANNEL:-dev}"
set_plist DNZEnvironment "${DNZ_ENVIRONMENT:-development}"
cp app-info.json "$APP/Contents/Resources/app-info.json"

# App icon: generate .icns from the single 1024px PNG
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Use a stable signing identity if provided (keeps the Screen Recording permission across rebuilds);
# otherwise ad-hoc. Hardened runtime is enabled either way.
IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"

echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/ZoomDNZ")"
echo "Built: $APP"
echo "Run:   open \"$APP\""
