#!/bin/bash
# pcrun.sh <label> [VAR=value ...]: one runq4 run with a startup timeline (boot/<label>.ts) beside it.
S=${S:-${TMPDIR:-/tmp}/fifa_harness}; mkdir -p "$S"   # scratch folder for logs and intermediate files
L=$1
while pgrep -f "fifa_autotest2.sh drive" >/dev/null || pgrep -x shadps4 >/dev/null; do sleep 5; done
bash $S/boot/bootwatch3.sh $L > /dev/null 2>&1 &
bash $S/runq4.sh "$@"
