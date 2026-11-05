#!/bin/bash
# Sample the running shadPS4 process (all threads) while a match is in progress.
#   bash ~/fifa_profile.sh [seconds]     default 20 s; writes ~/fifa_runs/<latest>/profile-<time>.txt
SECS="${1:-20}"
PID=$(pgrep -x shadps4 | head -1)
[ -z "$PID" ] && { echo "shadps4 is not running - start a match first"; exit 1; }
DIR=$(ls -td "$HOME/fifa_runs"/*/ 2>/dev/null | head -1); DIR="${DIR:-$HOME/fifa_runs}"
OUT="$DIR/profile-$(date +%H%M%S).txt"
echo "sampling pid $PID for ${SECS}s -> $OUT  (keep playing)"
sample "$PID" "$SECS" 1 -mayDie -file "$OUT" >/dev/null 2>&1 || sample "$PID" "$SECS" -file "$OUT"
echo "done: $(wc -l < "$OUT") lines"
