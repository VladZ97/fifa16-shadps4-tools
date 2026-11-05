#!/bin/zsh
# matchsheet.sh <label>: plays a match (autotest drive, env inherited), builds sheet_<label>.jpg of its shots.
L=$1; BB_RT_LOG=1 VIS_STATES=none MTL_HUD_ENABLED=1 bash ~/fifa_autotest.sh drive metal > ~/fifa_metal/autotest_ms_$L.log 2>&1
grep -E "VERDICT|FPS avg" ~/fifa_metal/autotest_ms_$L.log | tail -2
R=$(ls -td ~/fifa_metal/runs/*/ | head -1); echo "run $R"
magick montage $(ls $R/match_*.jpg) -tile 4x -geometry 640x376+2+2 ~/fifa_metal/sheet_$L.jpg && echo "sheet ~/fifa_metal/sheet_$L.jpg"
