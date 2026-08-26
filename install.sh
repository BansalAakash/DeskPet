#!/bin/bash
# Builds DeskPet from source and installs it.
#
#   curl -fsSL https://raw.githubusercontent.com/BansalAakash/DeskPet/main/install.sh | bash
#
# Building on your own Mac means macOS never marks the app as "downloaded
# from the internet", so there's no Gatekeeper warning to click through.
set -euo pipefail

REPO="BansalAakash/DeskPet"
SRC="https://github.com/$REPO/archive/refs/heads/main.tar.gz"
APP="DeskPet.app"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
die() { printf '\n\033[1;31m%s\033[0m\n' "$1" >&2; exit 1; }

# --- 1. macOS version -------------------------------------------------------
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MAJOR" -lt 13 ]; then
    die "DeskPet needs macOS 13 or later (this Mac is $(sw_vers -productVersion))."
fi

# --- 2. Swift toolchain -----------------------------------------------------
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
    say "DeskPet needs Apple's developer tools to build. Starting the installer..."
    echo "A system dialog will appear. Click Install, wait for it to finish,"
    echo "then run this command again."
    xcode-select --install >/dev/null 2>&1 || true
    exit 1
fi

# --- 3. Fetch the source ----------------------------------------------------
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

say "Downloading DeskPet..."
curl -fsSL "$SRC" | tar xz -C "$WORK" || die "Download failed. Check your internet connection."
DIR=$(find "$WORK" -maxdepth 1 -type d -name "DeskPet-*" | head -1)
[ -n "$DIR" ] || die "Downloaded archive didn't look right."

# --- 4. Build ---------------------------------------------------------------
say "Building (this takes about a minute)..."
( cd "$DIR" && ./Scripts/build_app.sh >/dev/null ) || die "Build failed."

# --- 5. Choose where it goes ------------------------------------------------
# Managed Macs often don't allow writing to /Applications.
if [ -w /Applications ]; then
    DEST="/Applications"
else
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi

# --- 6. Install -------------------------------------------------------------
pkill -f "$APP/Contents/MacOS/DeskPet" 2>/dev/null || true
sleep 1
rm -rf "${DEST:?}/$APP"
cp -R "$DIR/$APP" "$DEST/"

say "Installed to $DEST/$APP"
open "$DEST/$APP"

cat <<EOF

DeskPet is running — look for the 🐾 in your menu bar.

  • Click the paw for settings, or "Peek Now" to summon one immediately.
  • Turn on "Open at Login" there if you want it to start with your Mac.
  • To remove it: quit from the menu, then drag it out of $DEST.

Because you built it yourself, macOS raised no security warning.
EOF
