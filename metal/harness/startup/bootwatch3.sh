#!/bin/bash
# bootwatch3.sh <label>: timestamps selected emulator.log lines of the next run for 110 s (no sampling).
S=${S:-${TMPDIR:-/tmp}/fifa_harness}; mkdir -p "$S"   # scratch folder for logs and intermediate files
L=$1; R=$HOME/fifa_metal/runs
last=$(ls -d $R/2*/ 2>/dev/null | tail -1)
for i in $(seq 1 3000); do
  cur=$(ls -d $R/2*/ 2>/dev/null | tail -1)
  [ "$cur" != "$last" ] && [ -f "$cur/emulator.log" ] && break
  sleep 0.2
done
[ "$cur" = "$last" ] && { echo "no new run"; exit 1; }
echo "run $cur" > $S/boot/$L.ts
( tail -n +1 -F "$cur/emulator.log" 2>/dev/null | LC_ALL=C python3 -u -c '
import sys, time
t0 = time.time(); n = 0
out = open(sys.argv[1], "a")
for raw in sys.stdin.buffer:
    n += 1
    t = time.time() - t0
    if t > 110: break
    s = raw.decode("latin1")
    if ("PATCHCACHE" in s or "STARTUP" in s or "open:" in s or "Frame stats" in s or "LoadStartModule" in s or "bbgpu-host:" in s or "Mount" in s
        or "getdents" in s or "Shader" in s or "seed" in s or "pthread_rename" in s or n % 200 == 0):
        out.write("%7.2f %6d %s\n" % (t, n, s.strip()[:230])); out.flush()
' $S/boot/$L.ts ) &
TP=$!
sleep 112; kill $TP 2>/dev/null; pkill -f "tail -n +1 -F $cur/emulator.log" 2>/dev/null
echo done >> $S/boot/$L.ts
