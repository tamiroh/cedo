#!/bin/sh
# Build in release mode and assemble build/cedo.app
set -eu
cd "$(dirname "$0")/.."

swift build -c release
app=build/cedo.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/cedo" "$app/Contents/MacOS/cedo"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>cedo</string>
    <key>CFBundleExecutable</key><string>cedo</string>
    <key>CFBundleIdentifier</key><string>com.tamiroh.cedo</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
echo "Built $app"
