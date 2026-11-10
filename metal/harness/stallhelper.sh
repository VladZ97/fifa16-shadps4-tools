#!/bin/bash
# stallhelper.sh <label>: (a) snapshots in cutscene windows (>= 700 draws, 5 at most, 6 s apart);
# (b) when an [FSTAT] window shows >= 3 hitches at a normal frame rate with a busy GPU (the periodic game-side
# stall in some cutscenes), samples the emulator for 4 s and takes a snapshot (3 times at most).
export LC_ALL=C
S=${S:-${TMPDIR:-/tmp}/fifa_harness}; mkdir -p "$S"   # scratch folder for logs and intermediate files
R=$S/results/$1.txt
for i in $(seq 1 240); do grep -q "match running at" "$R" 2>/dev/null && break; grep -q "=== done" "$R" 2>/dev/null && exit 0; sleep 5; done
D=$(grep -a "^run dir" "$R" | head -1 | cut -d' ' -f3)
L=${D}emulator.log
seen=$(grep -a -c "\[FSTAT\]" "$L"); samples=0; snaps=0; last=0
while ! grep -q "=== done" "$R"; do
  sleep 0.5
  now=$(grep -a -c "\[FSTAT\]" "$L"); [ "$now" -le "$seen" ] && continue; seen=$now
  line=$(grep -a "\[FSTAT\]" "$L" | tail -1)
  ok=$(echo "$line" | awk '{split($2,f,"="); split($6,h,"="); split($7,g,"="); if (h[2]>=3 && f[2]>=45 && g[2]+0>=11) print 1}')
  if [ "$ok" = 1 ] && [ $samples -lt 3 ]; then
    samples=$((samples+1)); pid=$(pgrep -x shadps4 | head -1)
    echo "sample $samples pid $pid at $(date +%T): $line" >> $S/results/$1.stall
    echo "$S/capdiag/$1_stall$samples.png" > $S/snap.trigger
    sample "$pid" 4 1 -file $S/results/$1.sample$samples.txt >/dev/null 2>&1
    continue
  fi
  draws=$(grep -a "Frame stats" "$L" | tail -1 | sed -E 's/.* ([0-9]+) draws\/frame.*/\1/')
  if [ "$draws" -ge 700 ] 2>/dev/null && [ $snaps -lt 5 ] && [ $((SECONDS-last)) -ge 6 ]; then
    snaps=$((snaps+1)); last=$SECONDS
    echo "$S/capdiag/$1_cut$snaps.png" > $S/snap.trigger; echo "cut snap $snaps draws $draws: $line" >> $S/results/$1.stall
  fi
done
