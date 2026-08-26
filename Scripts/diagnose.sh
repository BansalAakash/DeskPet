#!/bin/bash
# Prints a short summary of why DeskPet quit, small enough to read off the
# screen or photograph.
#
#   curl -fsSL https://raw.githubusercontent.com/BansalAakash/DeskPet/main/Scripts/diagnose.sh | bash
set -uo pipefail

printf '\n\033[1m== DeskPet diagnosis ==\033[0m\n\n'

printf 'macOS   : %s (%s)\n' "$(sw_vers -productVersion)" "$(uname -m)"
printf 'Displays: %s\n' "$(system_profiler SPDisplaysDataType 2>/dev/null | grep -c Resolution)"

APP=$(ls -d /Applications/DeskPet.app "$HOME/Applications/DeskPet.app" 2>/dev/null | head -1)
if [ -n "$APP" ]; then
    printf 'Installed: %s\n' "$APP"
    printf 'Signature: %s\n' "$(codesign -dv "$APP" 2>&1 | grep -c 'Signature=adhoc' | sed 's/1/ad-hoc (built locally or downloaded)/;s/0/none/')"
else
    printf 'Installed: not found in /Applications or ~/Applications\n'
fi

printf 'Running  : %s process(es)\n' "$(pgrep -f 'DeskPet.app/Contents/MacOS/DeskPet' | wc -l | tr -d ' ')"

LOG=$(ls -t "$HOME"/Library/Logs/DiagnosticReports/DeskPet*.ips 2>/dev/null | head -1)

if [ -z "$LOG" ]; then
    cat <<'EOF'

No crash report found.

That usually means DeskPet is not crashing but being shut down by something
else — most often security software on a managed Mac. To confirm, run:

    /Applications/DeskPet.app/Contents/MacOS/DeskPet

then click "Peek Now". If it dies with no message at all, something outside
the app is killing it, and your IT team would need to allow it.
EOF
    exit 0
fi

printf '\nCrash report: %s\n' "$(basename "$LOG")"

python3 - "$LOG" <<'PY' 2>/dev/null || printf '(could not parse the report — send a photo of %s instead)\n' "$LOG"
import json, sys

path = sys.argv[1]
with open(path) as f:
    f.readline()                      # first line is a small header
    report = json.load(f)

print(f"When        : {report.get('captureTime', '?')}")
print(f"Exception   : {report.get('exception', {}).get('type', '?')} "
      f"{report.get('exception', {}).get('signal', '')}")

termination = report.get("termination")
if termination:
    print(f"Terminated  : {termination.get('namespace', '?')} — "
          f"{termination.get('reasons') or termination.get('indicator', '')}")
    if termination.get("byProc"):
        print(f"Killed by   : {termination['byProc']} (pid {termination.get('byPid')})")

images = report.get("usedImages", [])
faulting = next((t for t in report.get("threads", []) if t.get("triggered")), None)
if faulting:
    print("\nWhere it stopped (most recent first):")
    for frame in faulting.get("frames", [])[:6]:
        idx = frame.get("imageIndex", -1)
        name = images[idx].get("name", "?") if 0 <= idx < len(images) else "?"
        print(f"   {name}  {frame.get('symbol', '')}")
PY

cat <<'EOF'

What this means:
  • "Killed by" naming another process  -> security software; ask IT to allow it.
  • Frames mentioning DeskPet           -> a real bug; send this screen over.
  • EXC_CRASH / SIGKILL with no frames  -> also usually a policy kill.
EOF
