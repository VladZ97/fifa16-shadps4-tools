#!/bin/zsh
# balltest.sh <mesh file> <label>: links <mesh file> as ball_131.rx3 (the LaLiga ball of the test match) in the
# Metal overlay, plays a match drive (SHAD_STACK_CHK_IGNORE unset: a stack-check failure ends the run), reports
# crash lines with the module offset, then restores the overlay link. Side-only: Manual Install untouched.
set -u
MESH=$1; L=$2; B=~/fifa_perf/overlay/CUSA02138.fip/data/sceneassets/ball/ball_131.rx3
ORIG=$(readlink "$B"); echo "ball_131 was -> $ORIG"
ln -sfn "$MESH" "$B"; ls -la "$B"
SAMPLE_SECS=${SAMPLE_SECS:-40} VIS_STATES=none MTL_HUD_ENABLED=1 bash ~/fifa_autotest.sh drive metal > ~/fifa_metal/autotest_ball_$L.log 2>&1
R=$(ls -d ~/fifa_metal/runs/*/ | sort | tail -1); echo "run $R"
grep -h "VERDICT\|FPS avg\|EXITED" ~/fifa_metal/autotest_ball_$L.log | tail -3
sed -E 's/\x1b\[[0-9;]*m//g' $R/emulator.log | grep -a "stack_chk\|called from\|Unhandled\|SignalHandler\|Crash" | head -5
ln -sfn "$ORIG" "$B"; echo "restored ball_131 -> $(readlink $B)"
