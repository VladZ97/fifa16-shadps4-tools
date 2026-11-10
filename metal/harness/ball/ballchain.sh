#!/bin/bash
# ballchain.sh <label> [VAR=value ...]: one match with snapshots, draw logs and dumps of the ball shader's textures.
S=${S:-${TMPDIR:-/tmp}/fifa_harness}; mkdir -p "$S"   # scratch folder for logs and intermediate files
cd $S
L=$1; shift; D=$S/ball/dump_$L; mkdir -p $D
rm -f $S/results/$L.txt $S/dump.trigger $S/drawlog.trigger $S/snap.trigger
(bash $S/runq4.sh $L BB_DRAWLOG_TRIGGER=$S/drawlog.trigger BB_SNAPSHOT_TRIGGER=$S/snap.trigger BB_DUMP_BIND=da9fcd20:0,da9fcd20:1,da9fcd20:2,da9fcd20:3 BB_DUMP_BIND_MAX=8 BB_DUMP_BIND_TRIGGER=$S/dump.trigger BB_DUMP_DIR=$D "$@" > $S/${L}_run.out 2>&1 &)
(KICK_DELAYS="1 3 3 4 5 8 10 12 14 14" bash $S/kickhelper.sh $L > $S/${L}_helper.out 2>&1 &)
(for i in $(seq 1 480); do grep -q "match running at" $S/results/$L.txt 2>/dev/null && break; grep -q "=== done" $S/results/$L.txt 2>/dev/null && exit 0; sleep 2; done; sleep 6; touch $S/dump.trigger) &
for i in $(seq 1 130); do grep -q "=== done" $S/results/$L.txt 2>/dev/null && break; sleep 10; done
sleep 3
echo "== $L $(sort -u $S/results/$L.txt | grep -a VERDICT | head -1) $(sort -u $S/results/$L.txt | grep -a 'FPS avg' | head -1)"
R=$(grep -a "^run dir" $S/results/$L.txt | head -1 | cut -d' ' -f3)
cp $R/emulator.log $S/lat/${L}_emulator.log; echo "$L $R" >> $S/lat/rundirs.txt
echo "ballchain $L finished $(date +%H:%M:%S)"
