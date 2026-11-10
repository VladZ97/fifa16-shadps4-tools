#!/bin/bash
S=${BB_QUEUE_DIR:-$HOME/fifa_metal/queue}
LOG=$S/guard.log; RUN_MAX=${RUN_MAX:-1100}; ORPHAN_MAX=${ORPHAN_MAX:-120}; IDLE_MAX=${IDLE_MAX:-1000}; HELPER_MAX=${HELPER_MAX:-300}
age() { local st; st=$(ps -o lstart= -p "$1" 2>/dev/null) || return 1; [ -z "$st" ] && return 1; echo $(( $(date +%s) - $(date -j -f '%a %b %d %T %Y' "$st" +%s) )); }
note() { echo "$(date '+%H:%M:%S') GUARD: $*" | tee -a "$LOG"; local f; f=$(ls -t $S/results/*.txt 2>/dev/null | head -1); [ -n "$f" ] && echo "GUARD: $*" >> "$f"; }
killrun() { pkill -f 'fifa_autotest2.sh drive|autotest_app.sh drive' 2>/dev/null; sleep 1; pkill -x shadps4 2>/dev/null; pkill -f 'bbgpu-host' 2>/dev/null; sleep 3; pkill -9 -x shadps4 2>/dev/null; pkill -9 -f 'bbgpu-host' 2>/dev/null; }
orphan_since=""; norun_since=""
while :; do
  D=$(pgrep -f 'fifa_autotest2.sh drive|autotest_app.sh drive' | head -1)
  if [ -n "$D" ]; then
    orphan_since=""; norun_since=""
    A=$(age "$D"); if [ -n "$A" ] && [ "$A" -gt "$RUN_MAX" ]; then note "autotest pid $D alive ${A}s > ${RUN_MAX}s: killing run"; killrun; fi
    f=$(ls -t $S/results/*.txt 2>/dev/null | head -1)
    if [ -n "$f" ] && ! grep -q '=== done' "$f"; then
      idle=$(( $(date +%s) - $(stat -f %m "$f") ))
      if [ "$idle" -gt "$IDLE_MAX" ]; then note "$(basename $f) idle ${idle}s > ${IDLE_MAX}s: killing run"; killrun; fi
    fi
  else
    if pgrep -x shadps4 >/dev/null || pgrep -f 'bbgpu-host' >/dev/null; then
      orphan_since=${orphan_since:-$(date +%s)}
      if [ $(( $(date +%s) - orphan_since )) -gt "$ORPHAN_MAX" ]; then note "emulator/host without a driver for >${ORPHAN_MAX}s: killing orphans"; killrun; orphan_since=""; fi
    else orphan_since=""; fi
    # a sampler waiting for a run that is not there (its chain waits for it): kill it after HELPER_MAX s
    if pgrep -f '^/bin/bash .*cutsample' >/dev/null && [ ! -e "$S/build.lock" ]; then
      norun_since=${norun_since:-$(date +%s)}
      if [ $(( $(date +%s) - norun_since )) -gt "$HELPER_MAX" ]; then note "sampler without a run for >${HELPER_MAX}s: killing it"; pkill -f '^/bin/bash .*cutsample'; norun_since=""; fi
    else norun_since=""; fi
  fi
  sleep 30
done
