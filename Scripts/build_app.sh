#!/bin/bash
# Builds DeskPet.app in the project root.
#
#   ./Scripts/build_app.sh          shipping build (no development checks)
#   ./Scripts/build_app.sh --dev    same, plus the PEEK_* development checks
set -euo pipefail

cd "$(dirname "$0")/.."

DEV=0
[ "${1:-}" = "--dev" ] && DEV=1

if [ "$DEV" = "1" ]; then
    swift build -c release -Xswiftc -DPEEK_DEV
else
    swift build -c release
fi

APP="DeskPet.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/DeskPet "$APP/Contents/MacOS/"
# Bundle.module resolves against the app's Resources directory.
cp -R .build/release/DeskPet_DeskPet.bundle "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>DeskPet</string>
    <key>CFBundleDisplayName</key>
    <string>DeskPet</string>
    <key>CFBundleIdentifier</key>
    <string>com.aakash.deskpet</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>DeskPet</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
PLIST

# Ad-hoc signature. Gives the app a stable code identity, which macOS wants
# before it will keep a login item registered, and stops Gatekeeper
# re-verifying it on every launch. It is not a Developer ID signature, so a
# copy downloaded from the internet would still be quarantined.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1

if codesign --verify --strict "$APP" 2>/dev/null; then
    SIGNED="signed (ad-hoc)"
else
    SIGNED="UNSIGNED — codesign failed"
fi

SIZE=$(du -sh "$APP" | cut -f1)
echo "Built $APP  [$SIZE, $SIGNED$([ "$DEV" = "1" ] && echo ", development checks included")]"
