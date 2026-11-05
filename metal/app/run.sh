#!/bin/bash
# FIFA 16.app - launch logic. Lives in the bundle (Contents/Resources/run.sh); every location comes
# from the environment the launcher sets, nothing is hard-wired to a home folder:
#   FIFA_APP        the .app bundle            FIFA_DATA_DIR   ~/Library/Application Support/FIFA 16
#   FIFA_GAME_DIR   folder with eboot.bin      FIFA_UPDATE_DIR update 1.07 folder (optional)
#   FIFA_MODS_DIR   patch/mods overlay, served as /download0 (optional; <mods>/app0 overlays /app0)
#   FIFA_SAVES_DIR  savegame root (saves land in <root>/<user>/savedata/CUSA02138)
# Options (set only to change the default): BB_FULLSCREEN=0, BB_PRESENT_MODE=Immediate,
# BB_FRAME_STATS=1, MTL_HUD_ENABLED=1, KK_FLAGS, SHAD_READBACK_TILED.
#
#   run.sh play      launch for playing (log reduced to errors)
#   run.sh start     launch with the full log (diagnostics)
#   run.sh stop | status | log | env
set -u
APP="${FIFA_APP:-$(cd "$(dirname "$0")/../.." && pwd)}"
RES="$APP/Contents/Resources"
EMU="$RES/emulator/shadps4"
HOST="$APP/Contents/Helpers/FIFA 16 GPU.app/Contents/MacOS/bbgpu-host"
DATA="${FIFA_DATA_DIR:-$HOME/Library/Application Support/FIFA 16}"
USERDIR="$DATA/user"; RUNS="$DATA/runs"
GAME_DIR="${FIFA_GAME_DIR:-}"; UPDATE_DIR="${FIFA_UPDATE_DIR:-}"; MODS_DIR="${FIFA_MODS_DIR:-}"; SAVES_DIR="${FIFA_SAVES_DIR:-$DATA/saves}"
latest_run() { ls -d "$RUNS"/*/ 2>/dev/null | sort | tail -1; }

game_env() {
    export SHAD_USER_DIR="$USERDIR" SHAD_HOME_DIR="$SAVES_DIR"
    [ -n "$UPDATE_DIR" ] && export SHAD_UPDATE_DIR="$UPDATE_DIR"
    if [ -n "$MODS_DIR" ]; then
        export SHAD_DOWNLOAD_DIR="$MODS_DIR"
        [ -d "$MODS_DIR/app0" ] && export SHAD_MODS_DIR="$MODS_DIR/app0"
    fi
    export MESA_KK_EXPERIMENTAL="${KK_FLAGS-image_view_min_lod,custom_border}"
    export SHAD_READBACK_TILED="${SHAD_READBACK_TILED:-16777216}"
    export SHAD_BBGPU="${SHAD_BBGPU:-1}" SHAD_BBGPU_SPLIT="${SHAD_BBGPU_SPLIT:-1}" BB_CONFIG="$RES/bbport.ini" \
           BB_ARENA_LAYOUT="${BB_ARENA_LAYOUT:-runs}" BB_READBACKS="${BB_READBACKS:-2}" \
           SHAD_MAPPING_BASE="${SHAD_MAPPING_BASE:-400000000}" BB_GPU_HOST="${BB_GPU_HOST:-$HOST}" \
           BB_GPU_WATCHDOG_MS="${BB_GPU_WATCHDOG_MS:-2000}" BB_READBACK_LINEAR="${BB_READBACK_LINEAR:-1}" \
           BB_DRAW_PIPE="${BB_DRAW_PIPE:-0}" BB_IMMEDIATE_FLIPS="${BB_IMMEDIATE_FLIPS:-1}" \
           BB_MIDFRAME_FLUSH_MS="${BB_MIDFRAME_FLUSH_MS:-3}" BB_FULLSCREEN="${BB_FULLSCREEN:-1}"
}

write_config() {  # user/config.json: from the template on first run; install_dirs and log filter kept current
    python3 - "$USERDIR/config.json" "$RES/config.template.json" "$(dirname "$GAME_DIR")" "$1" <<'PY'
import json, os, sys
cfg, tpl, parent, mode = sys.argv[1:5]
c = json.load(open(cfg if os.path.exists(cfg) else tpl))
c.setdefault("General", {})["install_dirs"] = [{"enabled": True, "path": parent}]
c.setdefault("Log", {})["filter"] = "*:error" if mode == "play" else ""
json.dump(c, open(cfg, "w"), indent=4)
PY
}

case "${1:-play}" in
    play|start)
        [ -f "$GAME_DIR/eboot.bin" ] || { echo "game folder not set or no eboot.bin in: $GAME_DIR" >&2; exit 1; }
        [ -x "$EMU" ] || { echo "emulator missing in the bundle: $EMU" >&2; exit 1; }
        mkdir -p "$USERDIR" "$RUNS" "$SAVES_DIR"
        write_config "$1"
        pkill -x shadps4 2>/dev/null && sleep 1
        DIR="$RUNS/$(date +%Y%m%d_%H%M%S)"; mkdir -p "$DIR"
        game_env
        echo "run dir : $DIR"; echo "game    : $GAME_DIR"; echo "update  : ${UPDATE_DIR:-none}"; echo "mods    : ${MODS_DIR:-none}"; echo "saves   : $SAVES_DIR"
        cd "$DIR" || exit 1
        nohup "$EMU" --game "$GAME_DIR/eboot.bin" > "$DIR/emulator.log" 2>&1 &
        PID=$!; echo $PID > "$DIR/pid"
        sleep 3
        if kill -0 $PID 2>/dev/null; then echo "emulator pid $PID is running"; else echo "emulator exited early; last log lines:"; tail -5 "$DIR/emulator.log"; exit 1; fi ;;
    stop)   pkill -x shadps4 2>/dev/null && echo "emulator stopped" || echo "emulator was not running"; pkill -f 'bbgpu-host' 2>/dev/null; true ;;
    status) if pgrep -x shadps4 >/dev/null; then echo "running (pid $(pgrep -x shadps4 | head -1))"; else echo "not running"; fi
            R=$(latest_run); [ -n "$R" ] && { echo "latest run: $R"; grep -E 'FSTAT|Scoreboard|CRASH|Assertion' "$R/emulator.log" 2>/dev/null | tail -3; } ;;
    log)    R=$(latest_run); [ -n "$R" ] && tail -f "$R/emulator.log" ;;
    env)    game_env; env | grep -E '^(SHAD_|BB_|MESA_|MTL_)' | sort ;;
    *)      sed -n 2,14p "$0"; exit 1 ;;
esac
