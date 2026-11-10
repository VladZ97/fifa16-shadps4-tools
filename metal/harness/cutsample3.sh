#!/bin/bash
# cutsample2.sh <label>: once the run is in the match, sample the GPU host (exact process name, never pgrep -f)
# whenever the last Frame stats line shows >= 700 draws/frame; up to 3 samples of 4 s at 1 ms. Exits when the run ends.
S=${BB_QUEUE_DIR:-$HOME/fifa_metal/queue}
L=$1; T0=$(date +%s)
until grep -q -- '-> in_match' $S/results/$L.txt 2>/dev/null; do
  grep -q '=== done' $S/results/$L.txt 2>/dev/null && { echo "run ended before the match"; exit 0; }
  [ $(( $(date +%s) - T0 )) -gt 1300 ] && { echo "gave up waiting for the match"; exit 0; }; sleep 5; done
R=$(ls -d ~/fifa_metal/runs/*/ | sort | tail -1); n=0
hostpid() { ps -axo pid,comm | awk '$0 ~ /bbgpu-host/ {print $1; exit}'; }   # the bundle path has a space
while [ $n -lt 3 ] && pgrep -x shadps4 >/dev/null; do
  D=$(grep -a 'Frame stats' "$R/emulator.log" | tail -1 | grep -oE '[0-9]+ draws/frame' | grep -oE '^[0-9]+')
  if [ -n "$D" ] && [ "$D" -ge 700 ]; then P=$(hostpid); [ -n "$P" ] && sample "$P" 4 1 -mayDie -file $S/results/$L.heavysample_$n.txt >/dev/null 2>&1 && echo "sample $n at $D draws/frame" && n=$((n+1))
  else sleep 2; fi
done
echo "heavy samples: $n"
