#!/bin/zsh
# FIFA 16 on shadPS4 (macOS) — SIDE (performance) build runner. Same config/cache/saves, different emulator binary + run dir.
#
#   bash ~/fifa_perf.sh start      launch the game with the current experiment settings + background monitor
#   bash ~/fifa_perf.sh play       same as start but for playing: emulator log reduced to errors, no screenshots/stats
#   bash ~/fifa_perf.sh stop       quit the game and the monitor
#   bash ~/fifa_perf.sh cache      show the shader/pipeline cache state (files, last warm-up result)
#   bash ~/fifa_perf.sh cache-backup   snapshot the cache to ~/fifa_cache_backups/<timestamp>
#   bash ~/fifa_perf.sh cache-restore  restore the newest snapshot (emulator must be stopped)
#   bash ~/fifa_perf.sh status     running? latest screenshot, FPS trend, GPU load, last errors
#   bash ~/fifa_perf.sh shots      list screenshots of the current/last run
#   bash ~/fifa_perf.sh log        tail the emulator log of the current/last run
#
# Knobs (environment variables, all optional):
#   KK_FLAGS      KosmicKrisp experimental flags  (default: image_view_min_lod,custom_border ; "" to disable)
#   SHOT_EVERY    seconds between screenshots      (default: 20)
#   MTL_VALIDATE  1 = run under Metal API validation (very slow, for diagnostics)
#   PERF_SUBMIT   1 = overlapped submits experiment (side build only)
#   SHAD_STACK_CHK_IGNORE 1 = log failed stack checks and keep running (custom build)
#   SHAD_READBACK_TILED  max pixels of GPU-written tiled images to read back (custom build; default 16777216 = 4096x4096 (everything except screen-sized/depth images; needed for the kit composites), none = off)
#
# Each run writes to ~/fifa_runs/<timestamp>/ : emulator.log, shots/*.jpg, stats.txt, config.json (copy)

EMU="$HOME/Library/Application Support/shadPS4QtLauncher/versions/Custom-perf/shadps4"
GAME="${SIDE_GAME:-/Volumes/SanDiskSSD/F16_02138_extracted/F16_02138/FIFA 16 - CUSA02138 + Update 1.07/FIFA_16/CUSA02138/eboot.bin}"   # SIDE_GAME=<eboot path> overrides (e.g. ~/fifa_perf/game/CUSA02138/eboot.bin = symlinked game with SKIP_BOOTFLOW)
CFG="$HOME/Library/Application Support/shadPS4QtLauncher/versions/Custom-perf/user/config.json"
RUNS="$HOME/fifa_perf_runs"
: ${KK_FLAGS="image_view_min_lod,custom_border"}
: ${SHOT_EVERY=20}

latest_run() { ls -d "$RUNS"/*/ 2>/dev/null | sort | tail -1; }

window_id() {
  cat > /tmp/fifa_winid.swift <<'SW'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String:Any]]
var best: (Int, Double) = (0, 0)
for w in list where (w["kCGWindowOwnerName"] as? String) == "shadps4" {
  let b = w["kCGWindowBounds"] as! [String: Double]
  if b["Height"]! > best.1 { best = (w["kCGWindowNumber"] as! Int, b["Height"]!) }
}
print(best.0)
SW
  swift /tmp/fifa_winid.swift 2>/dev/null
}

monitor() {   # $1 = run dir, $2 = emulator pid
  local DIR="$1" PID="$2" WID="" n=0
  mkdir -p "$DIR/shots"
  while kill -0 "$PID" 2>/dev/null; do
    n=$((n+1)); local T=$(date +%H:%M:%S)
    local CPU=$(ps -o %cpu= -p "$PID" | tr -d ' ')
    local GPU=$(ioreg -r -c IOAccelerator 2>/dev/null | grep -oE '"Device Utilization %"=[0-9]+' | grep -oE '[0-9]+$' | head -1)
    local RSS=$(ps -o rss= -p "$PID" | tr -d ' ')
    echo "$T cpu=${CPU}% gpu=${GPU}% rss=$((RSS/1024))MB" >> "$DIR/stats.txt"
    [ -z "$WID" ] || [ "$WID" = "0" ] && WID=$(window_id)
    if [ -n "$WID" ] && [ "$WID" != "0" ]; then
      screencapture -x -o -l "$WID" -t jpg "$DIR/shots/$(date +%H%M%S).jpg" 2>/dev/null
      ls -t "$DIR/shots"/*.jpg 2>/dev/null | tail -n +61 | xargs rm -f 2>/dev/null
    fi
    sleep "$SHOT_EVERY"
  done
  echo "$(date +%H:%M:%S) emulator exited" >> "$DIR/stats.txt"
}

if [ "${1:-}" = play ]; then PLAY_MODE=1; set -- start; fi
case "${1:-start}" in
  start)
    if [ -n "${PLAY_MODE:-}" ]; then
      SHOT_EVERY=0
      python3 -c "import json,sys; p=sys.argv[1]; c=json.load(open(p)); c.setdefault('Log',{})['filter']='*:error'; json.dump(c,open(p,'w'),indent=4)" "$CFG" && touch "$CFG.playmode"
    elif [ -f "$CFG.playmode" ]; then
      python3 -c "import json,sys; p=sys.argv[1]; c=json.load(open(p)); c.setdefault('Log',{})['filter']=''; json.dump(c,open(p,'w'),indent=4)" "$CFG"; rm -f "$CFG.playmode"
    fi
    pkill -x shadps4 2>/dev/null && sleep 1
    # prune old runs: keep the 10 newest folders, drop screenshots of all but the 3 newest
    ls -td "$RUNS"/*/ 2>/dev/null | tail -n +11 | xargs rm -rf 2>/dev/null
    for d in $(ls -td "$RUNS"/*/ 2>/dev/null | tail -n +4); do rm -rf "$d/shots" 2>/dev/null; done
    DIR="$RUNS/$(date +%Y%m%d_%H%M%S)"; mkdir -p "$DIR"
    cp "$CFG" "$DIR/config.json"
    export MESA_KK_EXPERIMENTAL="$KK_FLAGS"
    [ -n "${SHAD_STACK_CHK_IGNORE:-}" ] && export SHAD_STACK_CHK_IGNORE
    # side-build experiments: PERF_SUBMIT=1 = no submission lock + copied command buffers (frame overlap)
    if [ "${PERF_SUBMIT:-0}" = "1" ]; then export SHAD_NO_SUBMISSION_LOCK=1 SHAD_COPY_GPU_BUFFERS=1; echo "experiment: overlapped submits ON"; fi
    if [ "${SHAD_READBACK_TILED:-}" = none ]; then unset SHAD_READBACK_TILED; else export SHAD_READBACK_TILED="${SHAD_READBACK_TILED:-16777216}"; fi
    if [ "${MTL_VALIDATE:-0}" = "1" ]; then
      export MTL_DEBUG_LAYER=1 MTL_DEBUG_LAYER_ERROR_MODE=nslog MTL_DEBUG_LAYER_WARNING_MODE=nslog
    fi
    echo "run dir : $DIR"
    echo "KK flags: ${MESA_KK_EXPERIMENTAL:-<none>}   metal validation: ${MTL_VALIDATE:-0}"
    cd "$(dirname "$EMU")"
    nohup "$EMU" --game "$GAME" > "$DIR/emulator.log" 2>&1 &
    PID=$!; echo "$PID" > "$DIR/pid"
    if [ "${SHOT_EVERY}" != "0" ]; then
      nohup zsh -c "$(declare -f window_id monitor); SHOT_EVERY=$SHOT_EVERY; monitor '$DIR' $PID" > /dev/null 2>&1 &
      echo "$!" > "$DIR/monitor_pid"
    fi
    sleep 6
    if kill -0 $PID 2>/dev/null; then
      echo "emulator pid $PID is running; screenshots every ${SHOT_EVERY}s in $DIR/shots"
      grep -E "App Version|GPU_Vulkan_Driver|Extension VK_EXT_(image_view_min_lod|custom_border_color)" "$DIR/emulator.log" | sed -E 's/\x1b\[[0-9;]*m//g; s/^\[[^]]+\] <[^>]+> \([^)]+\) //'
    else
      echo "emulator exited early; last log lines:"; tail -5 "$DIR/emulator.log" | sed -E 's/\x1b\[[0-9;]*m//g'
    fi
    ;;
  stop)
    DIR=$(latest_run)
    pkill -x shadps4 2>/dev/null && echo "emulator stopped" || echo "emulator was not running"
    [ -n "$DIR" ] && [ -f "$DIR/monitor_pid" ] && kill "$(cat "$DIR/monitor_pid")" 2>/dev/null
    ;;
  status)
    DIR=$(latest_run); [ -z "$DIR" ] && { echo "no runs yet"; exit 0; }
    echo "run dir : $DIR"
    pgrep -x shadps4 >/dev/null && echo "emulator: RUNNING" || echo "emulator: not running"
    echo "--- last stats"; tail -3 "$DIR/stats.txt" 2>/dev/null
    echo "--- latest screenshot"; ls -t "$DIR/shots"/*.jpg 2>/dev/null | head -1
    echo "--- warnings/errors of interest"
    sed -E 's/\x1b\[[0-9;]*m//g' "$DIR/emulator.log" | grep -E "<Critical>|Unreachable|SignalHandler|Extension VK_EXT_(image_view_min_lod|custom_border_color)|App Version|Recompiler\] <Warning>" | sed -E 's/^\[[^]]+\] <[^>]+> \([^)]+\) //' | sort | uniq -c | tail -8
    ;;
  shots)
    DIR=$(latest_run); ls -t "$DIR/shots"/*.jpg 2>/dev/null
    ;;
  log)
    DIR=$(latest_run); sed -E 's/\x1b\[[0-9;]*m//g' "$DIR/emulator.log" | tail -${2:-40}
    ;;
  cache)
    C="$HOME/Library/Application Support/shadPS4/cache/CUSA02138"
    echo "cache dir : $C"; echo "files     : $(ls "$C" 2>/dev/null | wc -l | tr -d ' ')  size: $(du -sh "$C" 2>/dev/null | cut -f1)"
    DIR=$(latest_run); echo "last run  : $(grep -oE 'WarmUp: [^|]*|Pipeline cache[^|]*' "$DIR/emulator.log" 2>/dev/null | sed -E 's/\x1b\[[0-9;]*m//g' | head -2 | tr '\n' ' ')"
    echo "pipelines compiled in last run: $(grep -c 'Compiling graphics pipeline' "$DIR/emulator.log" 2>/dev/null)  (0 or low = cache working; play mode logs errors only, so use start to measure)"
    echo "backups   : $(ls -d "$HOME/fifa_cache_backups"/*/ 2>/dev/null | wc -l | tr -d ' ') in ~/fifa_cache_backups" ;;
  cache-backup)
    C="$HOME/Library/Application Support/shadPS4/cache/CUSA02138"; B="$HOME/fifa_cache_backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$B" && cp -R "$C" "$B/" && echo "cache backed up to $B ($(ls "$C" | wc -l | tr -d ' ') files)" ;;
  cache-restore)
    pgrep -x shadps4 >/dev/null && { echo "stop the emulator first"; exit 1; }
    C="$HOME/Library/Application Support/shadPS4/cache/CUSA02138"; B=$(ls -td "$HOME/fifa_cache_backups"/*/ 2>/dev/null | head -1)
    [ -z "$B" ] && { echo "no backups"; exit 1; }
    rm -rf "$C" && cp -R "$B/CUSA02138" "$C" && echo "restored $B" ;;
  *) echo "usage: $0 {start|play|stop|status|shots|log|cache|cache-backup|cache-restore}"; exit 1 ;;
esac
