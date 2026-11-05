#!/bin/zsh
# For 40 minutes: whenever the newest autotest log reports a loading hang and the emulator is alive, sample it once per run.
last=""
for i in $(seq 1 160); do
  sleep 15
  L=$(ls -t ~/fifa_metal/autotest_*.log 2>/dev/null | head -1)
  [ -z "$L" ] && continue
  if tail -1 "$L" | grep -q "no change in"; then
    P=$(pgrep -x shadps4 | head -1)
    if [ -n "$P" ] && [ "$P" != "$last" ]; then
      sample "$P" 3 -file ~/fifa_metal/hang_sample_$(date +%H%M%S).txt >/dev/null 2>&1
      echo "$(date +%T) sampled $P ($L)"; last="$P"
    fi
  fi
done
