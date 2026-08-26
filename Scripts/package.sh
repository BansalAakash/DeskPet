#!/bin/bash
# Produces CatsAndDogsPeek.zip, ready to attach to a GitHub release.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="CatsAndDogsPeek.app"
ZIP="CatsAndDogsPeek.zip"

./Scripts/build_app.sh

rm -f "$ZIP"
# ditto, not zip: it preserves the code signature and resource forks.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo
echo "$ZIP  ($(du -h "$ZIP" | cut -f1))"
echo
echo "The app is ad-hoc signed, so the first launch on someone else's Mac"
echo "needs one approval in System Settings > Privacy & Security."
echo "The README walks through it."
