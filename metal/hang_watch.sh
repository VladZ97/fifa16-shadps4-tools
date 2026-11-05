#!/bin/zsh
# Drives the hybrid through the match flow; if it sits in a loading state, samples the process and stops it.
LOG=~/fifa_metal/autotest_match4.log
MTL_HUD_ENABLED=1 bash ~/fifa_autotest.sh drive metal > "$LOG" 2>&1 &
DRV=$!
for i in $(seq 1 120); do
  sleep 10
  if grep -q "no change in loading_drill for 12 s+\|no change in loading" "$LOG"; then
    P=$(pgrep -x shadps4 | head -1)
    if [ -n "$P" ]; then
      sleep 45
      sample "$P" 3 -file ~/fifa_metal/hang_sample.txt >/dev/null 2>&1
      echo "sampled pid $P at $(date +%T)"
      kill "$P"
    fi
    break
  fi
  if ! kill -0 $DRV 2>/dev/null; then echo "drive finished"; break; fi
done
wait $DRV 2>/dev/null
tail -5 "$LOG" | cut -c1-160
