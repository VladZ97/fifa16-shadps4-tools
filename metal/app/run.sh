#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# F16.app - launch logic. Lives in the bundle (Contents/Resources/run.sh); every location comes
# from the environment the launcher sets, nothing is hard-wired to a home folder:
#   FIFA_APP        the .app bundle            FIFA_DATA_DIR   ~/Library/Application Support/FIFA 16
#   FIFA_GAME_DIR   folder with eboot.bin      FIFA_UPDATE_DIR update 1.07 folder (optional)
#   FIFA_MODS_DIR   patch/mods overlay, served as /download0 (optional; <mods>/app0 overlays /app0; empty: no mods at all)
#   FIFA_SAVES_DIR  savegame root (saves land in <root>/<user>/savedata/CUSA02138)
# Options (set only to change the default): BB_FULLSCREEN=0, BB_PRESENT_MODE=Immediate,
# BB_VBLANK_HZ=120 (120 Hz mode), BB_FRAME_STATS=1, MTL_HUD_ENABLED=1, KK_FLAGS, SHAD_READBACK_TILED.
#
#   run.sh play      launch for playing (log reduced to errors)
#   run.sh start     launch with the full log (diagnostics)
#   run.sh stop | status | log | env
set -u
APP="${FIFA_APP:-$(cd "$(dirname "$0")/../.." && pwd)}"
RES="$APP/Contents/Resources"
EMU="$RES/emulator/shadps4"
HOST="$APP/Contents/Helpers/F16 GPU.app/Contents/MacOS/bbgpu-host"
DATA="${FIFA_DATA_DIR:-$HOME/Library/Application Support/FIFA 16}"
USERDIR="$DATA/user"; RUNS="$DATA/runs"
GAME_DIR="${FIFA_GAME_DIR:-}"; UPDATE_DIR="${FIFA_UPDATE_DIR:-}"; MODS_DIR="${FIFA_MODS_DIR:-}"; SAVES_DIR="${FIFA_SAVES_DIR:-$DATA/saves}"
latest_run() { ls -d "$RUNS"/*/ 2>/dev/null | sort | tail -1; }
# Only this bundle's processes are ever touched: another shadPS4 on the Mac is not ours to stop.
own_emulators() { ps -axo pid=,command= | grep -F "$EMU" | grep -v grep | awk '{print $1}'; }
own_hosts() { ps -axo pid=,command= | grep -F "$APP/Contents/Helpers/" | grep bbgpu-host | grep -v grep | awk '{print $1}'; }
stop_own() { local p; p=$(own_emulators); [ -n "$p" ] && kill $p 2>/dev/null; p=$(own_hosts); [ -n "$p" ] && kill $p 2>/dev/null; sleep 1; }

# The caches the game builds while it runs (translated shaders, compiled pipelines, the record of
# the emulator's start-up patches) live in the savegame folder the user chose, in <saves>/cache,
# so they stay with the saves when that folder is moved or shared between installs. The
# emulator and the renderer look in <data>/user/cache, which is a link to it. A cache an older
# version left in the data folder is moved over once. No savegame folder to write to: a plain
# local cache folder, as before.
place_caches() {
    local link="$USERDIR/cache" dest="$SAVES_DIR/cache" e n
    if ! mkdir -p "$dest" 2>/dev/null || [ ! -w "$dest" ]; then
        [ -L "$link" ] && rm -f "$link"
        mkdir -p "$link"; return 0
    fi
    if [ -L "$link" ]; then
        [ "$(readlink "$link")" = "$dest" ] || { rm -f "$link"; ln -s "$dest" "$link"; }
        return 0
    fi
    if [ -d "$link" ]; then
        for e in "$link"/*; do
            [ -e "$e" ] || continue; n=$(basename "$e")
            rmdir "$dest/$n" 2>/dev/null || true      # an empty folder there does not count
            [ -e "$dest/$n" ] || mv "$e" "$dest/" 2>/dev/null || true
        done
        rm -rf "$link"
    fi
    ln -s "$dest" "$link"
}

game_env() {
    export SHAD_USER_DIR="$USERDIR" SHAD_HOME_DIR="$SAVES_DIR"
    # The renderer library (in the emulator and in the GPU host) resolves its own user folder:
    # BB_GPU_USER_DIR keeps its shader caches and trophy notice here too, not in the shared
    # ~/Library/Application Support/shadPS4 of another shadPS4 install. Captures likewise.
    export BB_GPU_USER_DIR="$USERDIR" BB_CAPTURE_DIR="$DATA/captures"
    # Nothing made from the game ships with the app: the shader cache and the emulator's record of
    # its start-up code patches are built on this Mac from the user's own game files (place_caches).
    unset BB_SHADER_SEED_DIR SHAD_PATCH_SEED_DIR
    [ -n "$UPDATE_DIR" ] && export SHAD_UPDATE_DIR="$UPDATE_DIR"
    if [ -n "$MODS_DIR" ]; then
        export SHAD_DOWNLOAD_DIR="$MODS_DIR"
        [ -d "$MODS_DIR/app0" ] && export SHAD_MODS_DIR="$MODS_DIR/app0"
    else
        # No mods: an empty folder, or the emulator would still serve a <game>-mods folder next to the game.
        mkdir -p "$DATA/no-mods"; export SHAD_MODS_DIR="$DATA/no-mods"
    fi
    export MESA_KK_EXPERIMENTAL="${KK_FLAGS-image_view_min_lod,custom_border}"
    export SHAD_READBACK_TILED="${SHAD_READBACK_TILED:-16777216}"
    [ -n "${SHAD_BBGPU_SPLIT:-}" ] && SHAD_BBGPU_SPLIT_SET=1   # asked for explicitly: no in-process fallback
    export SHAD_BBGPU="${SHAD_BBGPU:-1}" SHAD_BBGPU_SPLIT="${SHAD_BBGPU_SPLIT:-1}" BB_CONFIG="$RES/bbport.ini" \
           BB_ARENA_LAYOUT="${BB_ARENA_LAYOUT:-runs}" BB_READBACKS="${BB_READBACKS:-2}" \
           SHAD_MAPPING_BASE="${SHAD_MAPPING_BASE:-400000000}" BB_GPU_HOST="${BB_GPU_HOST:-$HOST}" \
           BB_GPU_WATCHDOG_MS="${BB_GPU_WATCHDOG_MS:-5000}" BB_READBACK_LINEAR="${BB_READBACK_LINEAR:-1}" BB_RB_DIRECT="${BB_RB_DIRECT:-2}" \
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
        [ -n "$(own_emulators)" ] && stop_own
        place_caches
        DIR="$RUNS/$(date +%Y%m%d_%H%M%S)"; mkdir -p "$DIR"
        game_env
        # First launch: the emulator reports how far it is with preparing the game's code here; the
        # game window shows it as a progress bar and the launcher in its status line.
        export BB_PROGRESS_FILE="$DIR/progress"
        echo "run dir : $DIR"; echo "game    : $GAME_DIR"; echo "update  : ${UPDATE_DIR:-none}"; echo "mods    : ${MODS_DIR:-none}"; echo "saves   : $SAVES_DIR"
        cd "$DIR" || exit 1
        nohup "$EMU" --game "$GAME_DIR/eboot.bin" > "$DIR/emulator.log" 2>&1 &
        PID=$!; echo $PID > "$DIR/pid"
        # The native GPU host (SHAD_BBGPU_SPLIT=1) must come up within a few seconds. Where it cannot
        # start at all (macOS 26: the host cannot reserve the game's address range), the game is
        # relaunched with the renderer inside the emulator instead (slower, but it plays). Only
        # when the split was not asked for explicitly.
        for i in $(seq 1 40); do
            sleep 0.25
            grep -q "GPU process: host pid" "$DIR/emulator.log" 2>/dev/null && break
            kill -0 $PID 2>/dev/null || break
            grep -q "the GPU process could not start" "$DIR/emulator.log" 2>/dev/null && break
        done
        if [ "${SHAD_BBGPU_SPLIT_SET:-}" != 1 ] && grep -q "the GPU process could not start" "$DIR/emulator.log" 2>/dev/null; then
            echo "the native GPU host could not start on this Mac (see $DIR/emulator-gpu-host.log); rendering inside the emulator instead"
            kill $PID 2>/dev/null; sleep 1; stop_own
            mv "$DIR/emulator.log" "$DIR/emulator-gpu-host.log"
            export SHAD_BBGPU_SPLIT=0
            nohup "$EMU" --game "$GAME_DIR/eboot.bin" > "$DIR/emulator.log" 2>&1 &
            PID=$!; echo $PID > "$DIR/pid"
            sleep 3
        fi
        if kill -0 $PID 2>/dev/null; then echo "emulator pid $PID is running"; else echo "emulator exited early; last log lines:"; tail -5 "$DIR/emulator.log"; exit 1; fi ;;
    stop)   if [ -n "$(own_emulators)" ]; then stop_own; echo "emulator stopped"; else echo "emulator was not running"; fi; true ;;
    status) if [ -n "$(own_emulators)" ]; then echo "running (pid $(own_emulators | head -1))"; else echo "not running"; fi
            R=$(latest_run); [ -n "$R" ] && { echo "latest run: $R"; grep -E 'FSTAT|Scoreboard|CRASH|Assertion' "$R/emulator.log" 2>/dev/null | tail -3; } ;;
    log)    R=$(latest_run); [ -n "$R" ] && tail -f "$R/emulator.log" ;;
    env)    game_env; env | grep -E '^(SHAD_|BB_|MESA_|MTL_)' | sort ;;
    *)      sed -n 2,14p "$0"; exit 1 ;;
esac
