#!/bin/zsh
# capdrive.sh <label>: plays a match (rain is set in the game) and captures one frame's pass list in open play
# (HUD fps >= 55) and one in a 30-fps scene (replay/cutscene) with the port's frame analyzer; screenshots at
# both moments. Output: captures_<label>/frame_*.txt, cap_<label>_{open,slow}.jpg, sheet_<label>.jpg
L=$1; T=~/fifa_metal/captures_$L; rm -rf "$T"; mkdir -p "$T"; TRIG=$T/trigger; LOG=~/fifa_metal/autotest_cap_$L.log
BB_CAPTURE_TRIGGER=$TRIG BB_CAPTURE_DIR=$T BB_DUMP_VOLUMES=$T BB_TONE_LOG=1 BB_DUMP_AFTER=${DUMP_AFTER:-150} BB_RT_LOG=1 BB_RESOLVE_LOG=1 HUD_ALL=1 VIS_STATES=none MTL_HUD_ENABLED=1 bash ~/fifa_autotest.sh drive metal > "$LOG" 2>&1 &
DRV=$!; got_open=0; got_slow=0; n_open=0
while kill -0 $DRV 2>/dev/null; do
  sleep 3
  REP=$(ls -td ~/fifa_metal/runs/*/ | head -1)/report.txt; line=$(grep -E "^[0-9]+s hud fps\|gpu\|frame=" "$REP" 2>/dev/null | tail -1); [ -z "$line" ] && continue
  fps=$(echo "$line" | sed -E 's/.*fps\|gpu\|frame=\|([0-9.]+)\|.*/\1/')
  if [ "$got_open" = 0 ] && [ "${fps%.*}" -ge 55 ] 2>/dev/null; then
    n_open=$((n_open+1)); [ $n_open -lt 3 ] && continue      # a few seconds into open play
    touch "$TRIG"; sleep 2; S=$(bash ~/fifa_autotest.sh shot metal | tail -1); cp "$S" ~/fifa_metal/cap_${L}_open.jpg
    echo "open-play capture at $(echo "$line" | cut -d' ' -f1) fps=$fps"; got_open=1
  elif [ "$got_open" = 1 ] && [ "$got_slow" = 0 ] && [ "${fps%.*}" -le 35 ] 2>/dev/null; then
    touch "$TRIG"; sleep 2; S=$(bash ~/fifa_autotest.sh shot metal | tail -1); cp "$S" ~/fifa_metal/cap_${L}_slow.jpg
    echo "slow-scene capture at $(echo "$line" | cut -d' ' -f1) fps=$fps"; got_slow=1
  fi
done
grep -E "VERDICT|FPS avg" "$LOG" | tail -2; ls -la "$T"/frame_*.txt 2>/dev/null | awk '{print $5, $9}'
R=$(ls -td ~/fifa_metal/runs/*/ | head -1); magick montage $(ls $R/match_*.jpg) -tile 4x -geometry 640x376+2+2 ~/fifa_metal/sheet_$L.jpg 2>/dev/null && echo "sheet ~/fifa_metal/sheet_$L.jpg"
