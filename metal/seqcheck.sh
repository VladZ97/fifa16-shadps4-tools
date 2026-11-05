#!/bin/zsh
# seqcheck.sh <label>: drives to the kit selection while a side loop screenshots every 4 s into seq_<label>/;
# prints hub (last shot before team_select) and kit-screen luma.
L=$1; LOG=~/fifa_metal/autotest_seq_$L.log; OUTD=~/fifa_metal/seq_$L; rm -rf "$OUTD"; mkdir -p "$OUTD"
STOP_WHEN="HOME.*HOME" STOP_UNLESS="BARCELONA|MADRID" DWELL_SAMPLES=3 VIS_STATES=none MTL_HUD_ENABLED=1 bash ~/fifa_autotest.sh drive metal > "$LOG" 2>&1 &
DRV=$!
sleep 20
while kill -0 $DRV 2>/dev/null; do
  S=$(bash ~/fifa_autotest.sh shot metal 2>/dev/null | tail -1); [ -f "$S" ] && cp "$S" "$OUTD/$(date +%H%M%S).jpg"
  sleep 4
done
for f in "$OUTD"/*.jpg; do printf "%s luma=%.3f\n" "$(basename $f .jpg)" "$(magick "$f" -colorspace gray -format '%[fx:mean]' info:)"; done
grep -E "hub|team_select|kit|dwell done" "$LOG" | head -12 | cut -c1-100
