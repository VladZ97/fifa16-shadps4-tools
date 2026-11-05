#!/bin/zsh
# darkloop.sh <n> <label>: n sequential match drives with the twin watch on; per run: fps, twin stats, sheet.
N=${1:-6}; L=${2:-dark}
for i in $(seq 1 $N); do
  BB_TWIN_WATCH=1 BB_REFRESH_LOG=1 BB_IMG_BINDS=1 SAMPLE_SECS=${SAMPLE_SECS:-90} VIS_STATES=none MTL_HUD_ENABLED=1 bash ~/fifa_autotest.sh drive metal > ~/fifa_metal/autotest_${L}_$i.log 2>&1
  R=$(ls -td ~/fifa_metal/runs/*/ | head -1)
  echo "=== run $i: $R $(grep -h 'FPS avg\|VERDICT' ~/fifa_metal/autotest_${L}_$i.log | tr '\n' ' ')"
  sed -E 's/\x1b\[[0-9;]*m//g' $R/emulator.log | grep -a "TWINWATCH\|REFRESH\|R32UP" > $R/twinwatch.txt
  grep -c "sync 0x" $R/twinwatch.txt | sed 's/^/  twinwatch lines: /'
  grep "registered\|created" $R/twinwatch.txt | head -8 | sed 's/^/  /'
  grep "sync 0x\|REFRESH" $R/twinwatch.txt | tail -8 | sed 's/^/  /'
  magick montage $(ls $R/match_*.jpg 2>/dev/null) -tile 4x -geometry 640x376+2+2 ~/fifa_metal/sheet_${L}_$i.jpg 2>/dev/null
done
echo "=== loop done"
