#!/bin/bash
# diaghelper.sh <label> : once the run reports the match, fires frame captures and lossless snapshots.
S=${S:-${TMPDIR:-/tmp}/fifa_harness}; mkdir -p "$S"   # scratch folder for logs and intermediate files
R=$S/results/$1.txt
for i in $(seq 1 240); do grep -q "match running at" "$R" 2>/dev/null && break; grep -q "=== done" "$R" 2>/dev/null && exit 0; sleep 5; done
n=0
for d in 12 10 10 10 10; do
  sleep $d; grep -q "=== done" "$R" && exit 0
  n=$((n+1)); echo "$S/capdiag/$1_snap$n.png" > $S/snap.trigger
  [ $n -le 2 ] && { sleep 1; touch $S/cap.trigger; }
done
