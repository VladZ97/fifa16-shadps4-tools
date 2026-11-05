#!/bin/zsh
# hubcheck.sh <label>: drives to the main menu (hub), takes a screenshot there, prints its mean luma.
L=$1; LOG=~/fifa_metal/autotest_hub_$L.log
STOP_AT=hub DWELL_SAMPLES=4 VIS_STATES=none MTL_HUD_ENABLED=1 bash ~/fifa_autotest.sh drive metal > "$LOG" 2>&1 &
DRV=$!
for i in $(seq 1 60); do
  sleep 3
  if grep -q "dwell hub" "$LOG"; then
    sleep 4; S=$(bash ~/fifa_autotest.sh shot metal | tail -1)
    cp "$S" ~/fifa_metal/hub_$L.jpg
    printf "HUB %s luma=%.3f (%s)\n" "$L" "$(magick "$S" -colorspace gray -format '%[fx:mean]' info:)" "$S"
    break
  fi
  kill -0 $DRV 2>/dev/null || { echo "HUB $L: drive ended early"; break; }
done
wait $DRV 2>/dev/null; grep -E "VERDICT|dwell done" "$LOG" | tail -1
