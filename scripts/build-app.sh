#!/bin/zsh
# Builds a release RimPy Light.app into ./dist.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/RimpyLight"

APP="dist/RimPy Light.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RimpyLight"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>RimPy Light</string>
    <key>CFBundleDisplayName</key><string>RimPy Light</string>
    <key>CFBundleIdentifier</key><string>local.rimpylight</string>
    <key>CFBundleExecutable</key><string>RimpyLight</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
du -sh "$APP"
echo "Built $APP"
