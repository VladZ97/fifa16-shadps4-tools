#!/bin/bash
# runq.sh <label> [VAR=value ...] : one autotest match run (metal target) with extra environment,
# results summarised into $RESULTS/<label>.txt (report + frame stats + latency lines + shots copy).
S=${S:-${TMPDIR:-/tmp}/fifa_harness}; mkdir -p "$S"   # scratch folder for logs and intermediate files
RESULTS=$S/results; label=$1; shift
for kv in "$@"; do export "$kv"; done
export BB_FRAME_STATS=${BB_FRAME_STATS:-1}; export VIS_STATES=none
# wait for any running autotest/emulator to finish
W=0; while pgrep -f "fifa_autotest2.sh drive" >/dev/null || pgrep -x shadps4 >/dev/null; do sleep 10; W=$((W+10)); [ $W -ge 1500 ] && { echo "runq3: wait exceeded 1500 s, killing leftovers" >&2; pkill -f "fifa_autotest2.sh drive"; pkill -x shadps4; pkill -f bbgpu-host; sleep 5; W=0; }; done
while [ -e "$S/build.lock" ]; do sleep 10; done   # a build rewrites the dylib the host loads
echo "=== $label: $* (started $(date +%H:%M:%S))" > "$RESULTS/$label.txt"
bash ~/fifa_autotest2.sh drive metal >> "$RESULTS/$label.txt" 2>&1 & AP=$!; ( sleep ${RUN_MAX:-1100}; kill -0 $AP 2>/dev/null && { echo "runq3: run exceeded ${RUN_MAX:-1100} s, killed" >> "$RESULTS/$label.txt"; pkill -f "fifa_autotest2.sh drive"; pkill -x shadps4; pkill -f bbgpu-host; } ) & TP=$!; wait $AP; kill $TP 2>/dev/null
R=$(ls -d ~/fifa_metal/runs/*/ | sort | tail -1)
echo "run dir $R" >> "$RESULTS/$label.txt"
{ echo "--- report"; cat "$R/report.txt"; echo "--- frame stats"; grep -a '\[MSAALOG\]\|\[FMASK\]\|\[DEFER\]\|\[HOIST\]\|\[COPYCS\]\|\[SPIN\]\|\[STALL\]\|Frame stats\|Protects:\|Latency\|GPU profile\|Encoder stats\|encoders/frame\|VideoOut: vblank\|refresh rate' "$R/emulator.log" | cut -c1-400 | tail -60; echo "--- errors"; grep -a -i 'Critical\|Unhandled\|assert\|Crash' "$R/emulator.log" | head -5; } >> "$RESULTS/$label.txt" 2>&1
mkdir -p "$RESULTS/$label.shots"; cp "$R"/shots/*.jpg "$RESULTS/$label.shots/" 2>/dev/null
echo "=== done $(date +%H:%M:%S)" >> "$RESULTS/$label.txt"
