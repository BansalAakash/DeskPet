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

NOTES=$(cat <<'EOF'
### Install

1. Download `CatsAndDogsPeek.zip` below, unzip it, and drag the app to your
   **Applications** folder.
2. Double-click it — **macOS will refuse to open it the first time.**
3. Open  → **System Settings → Privacy & Security**, scroll to the bottom,
   and click **Open Anyway**.

That approval is a one-time step, and it's only because the app isn't
notarised by Apple (which costs $99/year). The app has no network code and
needs no permissions — the full source is in this repo.

Requires macOS 13 or later.
EOF
)

if gh release view "$TAG" >/dev/null 2>&1; then
    echo "Updating existing release $TAG..."
    gh release upload "$TAG" CatsAndDogsPeek.zip --clobber
else
    gh release create "$TAG" CatsAndDogsPeek.zip \
        --title "Cats & Dogs Peek $TAG" \
        --notes "$NOTES"
fi

echo
echo "Released $TAG"
gh release view "$TAG" --json url --jq .url
