#!/bin/zsh
# kitcheck.sh <label>: drives to the kit selection, screenshots it, prints the Barça shirt and RM face colours.
L=$1; LOG=~/fifa_metal/autotest_kit_$L.log
STOP_WHEN="HOME.*HOME" STOP_UNLESS="BARCELONA|MADRID" DWELL_SAMPLES=4 VIS_STATES=none MTL_HUD_ENABLED=1 bash ~/fifa_autotest.sh drive metal > "$LOG" 2>&1 &
DRV=$!
for i in $(seq 1 80); do
  sleep 3
  if grep -q "dwell " "$LOG"; then
    sleep 4; S=$(bash ~/fifa_autotest.sh shot metal | tail -1)
    cp "$S" ~/fifa_metal/kit_$L.jpg
    printf "KIT %s shirtL=%s shirtL2=%s faceR=%s shirtR=%s (%s)\n" "$L" \
      "$(magick "$S" -format '%[pixel:p{330,700}]' info: | sed 's/srgb//')" \
      "$(magick "$S" -format '%[pixel:p{380,560}]' info: | sed 's/srgb//')" \
      "$(magick "$S" -format '%[pixel:p{2140,420}]' info: | sed 's/srgb//')" \
      "$(magick "$S" -format '%[pixel:p{2120,620}]' info: | sed 's/srgb//')" "$S"
    break
  fi
  kill -0 $DRV 2>/dev/null || { echo "KIT $L: drive ended early"; break; }
done
wait $DRV 2>/dev/null; grep -E "VERDICT|dwell done" "$LOG" | tail -1
