#!/bin/sh
set -e
cd "$(dirname "$0")"
APP=MacCon.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 6 Sources/*.swift -o "$APP/Contents/MacOS/MacCon"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>MacCon</string>
<key>CFBundleIdentifier</key><string>com.local.maccon</string>
<key>CFBundleExecutable</key><string>MacCon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
</dict></plist>
PL
codesign --force --sign - "$APP" 2>/dev/null || true
echo "Built $APP"
