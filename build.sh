#!/bin/sh
# Builds MacCon.app (ad-hoc signed) in the project root.
set -e
cd "$(dirname "$0")"

swift build -c release
APP=MacCon.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/MacCon" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built $APP"
