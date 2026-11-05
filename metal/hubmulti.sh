#!/bin/zsh
# hubmulti.sh <label>: drives to the main menu and takes 6 screenshots 4 s apart, printing the
# grass/sky luma of each (the menu backdrop may animate; the spread matters).
L=$1; LOG=~/fifa_metal/autotest_hub_$L.log
STOP_AT=hub DWELL_SAMPLES=9 VIS_STATES=none MTL_HUD_ENABLED=1 bash ~/fifa_autotest.sh drive metal > "$LOG" 2>&1 &
DRV=$!
for i in $(seq 1 60); do
  sleep 3
  if grep -q "dwell hub" "$LOG"; then
    for k in 1 2 3 4 5 6; do
      S=$(bash ~/fifa_autotest.sh shot metal | tail -1); cp "$S" ~/fifa_metal/hub_${L}_$k.jpg
      printf "HUB %s #%d sky=%.3f grass=%.3f px=%s\n" "$L" "$k" "$(magick "$S" -crop 1100x260+0+70 +repage -colorspace gray -format '%[fx:mean]' info:)" "$(magick "$S" -crop 2560x220+0+1280 +repage -colorspace gray -format '%[fx:mean]' info:)" "$(magick "$S" -format '%[pixel:p{1280,1400}]' info: | sed 's/srgb//')"
      sleep 4
    done
    break
  fi
  kill -0 $DRV 2>/dev/null || { echo "HUB $L: drive ended early"; break; }
done
wait $DRV 2>/dev/null; grep -E "VERDICT|dwell done" "$LOG" | tail -1
