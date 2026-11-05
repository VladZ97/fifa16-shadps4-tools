#!/bin/zsh
# lattest.sh <label> : match drive with BB_FRAME_STATS=1 (env inherited, e.g. BB_VBLANK_HZ=0 BB_FPS_LIMIT=60);
# prints the Latency / Spikes / FSTAT lines of the in-match window and the match-clock vs wall-clock ratio.
L=$1
BB_FRAME_STATS=1 SAMPLE_SECS=${SAMPLE_SECS:-60} VIS_STATES=none MTL_HUD_ENABLED=1 bash ~/fifa_autotest.sh drive metal > ~/fifa_metal/autotest_lat_$L.log 2>&1
R=$(ls -td ~/fifa_metal/runs/*/ | head -1); echo "run $R"
grep -h "VERDICT\|FPS avg" ~/fifa_metal/autotest_lat_$L.log | tail -2
sed -E 's/\x1b\[[0-9;]*m//g' $R/emulator.log | grep -a "VideoOut: vblank\|^Latency\|^Spikes\|Frame pacing" > $R/latency.txt
echo "--- last 6 latency lines"; grep "^Latency" $R/latency.txt | tail -6
echo "--- last 3 spikes lines"; grep "^Spikes" $R/latency.txt | tail -3
echo "--- pacing"; grep "Frame pacing" $R/latency.txt | tail -3
grep -h "in_match" ~/fifa_metal/autotest_lat_$L.log | grep -oE "^[0-9]+s.*\|[0-9]{2}:[0-9]{2}" | sed -E 's/^([0-9]+)s.*\|([0-9]{2}:[0-9]{2})$/\1 \2/' | head -40 > $R/clock.txt
python3 - "$R/clock.txt" <<'PY'
import sys
rows=[l.split() for l in open(sys.argv[1]) if len(l.split())==2]
if len(rows)>=2:
    (t0,c0),(t1,c1)=rows[0],rows[-1]
    s=lambda c:int(c[:2])*60+int(c[3:])
    dw=int(t1)-int(t0); dc=s(c1)-s(c0)
    print(f"match clock {c0}->{c1} ({dc} s) over {dw} s wall: ratio {dc/dw if dw else 0:.2f} (FIFA half = 2 min per 45 game-min: expect ~{45*60/120:.1f}x)")
PY
magick montage $(ls $R/match_*.jpg 2>/dev/null) -tile 4x -geometry 640x376+2+2 ~/fifa_metal/sheet_lat_$L.jpg 2>/dev/null
