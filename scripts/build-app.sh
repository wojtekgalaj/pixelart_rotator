#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

BIN_DIR="$(swift build -c release --product PixelRotator --show-bin-path)"
APP="dist/Pixel Rotator.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp "$BIN_DIR/PixelRotator" "$APP/Contents/MacOS/PixelRotator"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>PixelRotator</string>
  <key>CFBundleIdentifier</key>
  <string>dev.wojtek.PixelRotator</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Pixel Rotator</string>
  <key>CFBundleDisplayName</key>
  <string>Pixel Rotator</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP"
