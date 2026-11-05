#!/bin/zsh
# Drives the hybrid into a match with HUD values logged in every state; when the loading drill
# (practice arena) is reached, samples the game and the GPU host for 3 s each (drill_sample_*.txt).
LOG=~/fifa_metal/autotest_drill.log
HUD_ALL=1 MTL_HUD_ENABLED=1 VIS_STATES="in_match" bash ~/fifa_autotest.sh drive metal > "$LOG" 2>&1 &
DRV=$!
for i in $(seq 1 120); do
  sleep 5
  if grep -q -- "-> loading_drill" "$LOG"; then
    sleep 12
    G=$(pgrep -x shadps4 | head -1); H=$(pgrep -f bbgpu-host | head -1)
    sample "$G" 3 -file ~/fifa_metal/drill_sample_game.txt >/dev/null 2>&1 &
    sample "$H" 3 -file ~/fifa_metal/drill_sample_host.txt >/dev/null 2>&1 &
    wait %2 %3 2>/dev/null
    echo "sampled game $G host $H at $(date +%T)"
    break
  fi
  if ! kill -0 $DRV 2>/dev/null; then echo "drive finished early"; break; fi
done
wait $DRV 2>/dev/null
echo "drive done: $(grep -E 'VERDICT|FPS avg' "$LOG" | tr '\n' ' ')"
