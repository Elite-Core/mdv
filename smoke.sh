#!/bin/sh
# Launches build/mdv.app, opens README.md into it, and fails unless the app logs a visible,
# rendered document window within 10s. release.sh runs this before tagging anything.
cd "$(dirname "$0")"
APP=build/mdv.app
LOG=$(mktemp)
pkill -x mdv 2>/dev/null || true; sleep 1
"$APP/Contents/MacOS/mdv" >"$LOG" 2>&1 &
PID=$!
sleep 2
open -a "$PWD/$APP" "$PWD/README.md"
for i in $(seq 1 20); do
  if grep -q "render loaded=1 doc=1 winVisible=1" "$LOG"; then
    kill $PID 2>/dev/null; wait $PID 2>/dev/null; rm -f "$LOG"; echo "smoke: document opened and rendered"; exit 0
  fi
  sleep 0.5
done
kill $PID 2>/dev/null; wait $PID 2>/dev/null
echo "smoke: FAILED — no visible rendered document within 10s. Log:"; grep "\[mdv\]" "$LOG" | sed -E 's/^.*\[mdv\]/[mdv]/'
rm -f "$LOG"; exit 1
