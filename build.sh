#!/usr/bin/env bash
set -euo pipefail

APP="Toggle Sleep.app"
BINARY="$APP/Contents/MacOS/ToggleSleep"

mkdir -p "$APP/Contents/MacOS"

echo "Compiling…"
swiftc -O -framework Cocoa \
    -o "$BINARY" \
    Sources/main.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>   <string>ToggleSleep</string>
    <key>CFBundleIdentifier</key>   <string>com.fabio.togglesleep</string>
    <key>CFBundleName</key>         <string>Toggle Sleep</string>
    <key>CFBundleVersion</key>      <string>1.0</string>
    <key>NSPrincipalClass</key>     <string>NSApplication</string>
    <key>LSUIElement</key>          <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

echo "Built: $APP"

if [[ "${1:-}" == "--install" ]]; then
    cp -r "$APP" /Applications/
    echo "Installed to /Applications/$APP"
fi
