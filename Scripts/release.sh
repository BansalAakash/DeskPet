#!/bin/bash
# Builds, zips, and publishes a GitHub release so people can download the app.
#
#   ./Scripts/release.sh v1.0
#
# Needs the GitHub CLI, logged in:  gh auth login
set -euo pipefail

cd "$(dirname "$0")/.."

TAG="${1:?usage: Scripts/release.sh <tag>   e.g. Scripts/release.sh v1.0}"

if ! gh auth status >/dev/null 2>&1; then
    echo "Not logged in to GitHub. Run:  gh auth login" >&2
    exit 1
fi

./Scripts/package.sh

# GitHub always adds "Source code (zip)" and "Source code (tar.gz)" to a
# release and there's no way to turn them off. They're a similar size to the
# app, so the app's file name has to say plainly what it is — otherwise
# people download the source by mistake and find nothing to open.
ASSET="CatsAndDogsPeek-${TAG}-macOS-app.zip"
rm -f "$ASSET"
cp CatsAndDogsPeek.zip "$ASSET"

NOTES=$(cat <<EOF
## Download

### ⬇️ [\`$ASSET\`](https://github.com/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/releases/download/$TAG/$ASSET) — this is the app

Ignore **Source code (zip)** and **Source code (tar.gz)** at the bottom of
this page unless you want to build it yourself. GitHub attaches those to
every release automatically; they contain the code, not a program you can
open.

## Install

1. Download **\`$ASSET\`**, unzip it, and drag \`CatsAndDogsPeek.app\` to your
   **Applications** folder.
2. Double-click it — **macOS will refuse to open it the first time.**
3. Open  → **System Settings → Privacy & Security**, scroll to the bottom,
   and click **Open Anyway**.

That approval is a one-time step, and it's only because the app isn't
notarised by Apple (which costs \$99/year). It isn't a warning about anything
the app does: there's no network code and no permissions are needed. All the
source is in this repo.

Requires macOS 13 or later.
EOF
)

if gh release view "$TAG" >/dev/null 2>&1; then
    echo "Updating existing release $TAG..."
    gh release upload "$TAG" "$ASSET" --clobber
    gh release edit "$TAG" --notes "$NOTES"
else
    gh release create "$TAG" "$ASSET" \
        --title "Cats & Dogs Peek $TAG" \
        --notes "$NOTES"
fi
rm -f "$ASSET"

echo
echo "Released $TAG"
gh release view "$TAG" --json url --jq .url
