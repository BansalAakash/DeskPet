#!/bin/bash
# Runs the development checks against a bundled app, so the resource layout
# and window behaviour are exercised exactly as they ship.
#
# These checks are compiled out of the shipping app; this script builds a
# separate copy with -DPEEK_DEV to include them.
#
# The "open at login" check registers and then unregisters a real login item,
# leaving the machine as it found it. If it is ever interrupted part-way,
# clear the leftover with:
#   PEEK_TEST_LOGINITEM=1 PEEK_LOGINITEM_CLEANUP=1 \
#       ./CatsAndDogsPeek.app/Contents/MacOS/CatsAndDogsPeek
set -euo pipefail

cd "$(dirname "$0")/.."

./Scripts/build_app.sh --dev
BIN="./CatsAndDogsPeek.app/Contents/MacOS/CatsAndDogsPeek"

status=0
run() {
    local label="$1" env_var="$2"
    printf '\n== %s ==\n' "$label"
    if ! env "$env_var=1" "$BIN" 2>&1 | tail -n "${3:-12}"; then
        status=1
    fi
}

run "geometry + assets" PEEK_SELFTEST 3
run "clicking"          PEEK_TEST_CLICK 12
run "peek now"          PEEK_TEST_PEEKNOW 8
run "face mix"          PEEK_TEST_FACES 4
run "open at login"     PEEK_TEST_LOGINITEM 8

printf '\nRebuilding without development checks...\n'
./Scripts/build_app.sh
exit $status
