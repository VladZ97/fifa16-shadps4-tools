#!/bin/bash
# Automated FIFA 16 test driver (side build by default).
#   bash ~/fifa_autotest.sh learn [main]   launch, screenshot every 2 s and log markers while YOU navigate to a
#                                          kick-off match; stop with: bash ~/fifa_autotest.sh stop. Produces timeline.txt
#   bash ~/fifa_autotest.sh run   [main]   launch and replay ~/fifa_perf/autotest/sequence.txt automatically, then
#                                          measure load times and FPS (OCR of the on-screen counter); writes report.txt
#   bash ~/fifa_autotest.sh stop           stop everything
#   bash ~/fifa_autotest.sh keys           test that key injection reaches the emulator (needs Accessibility permission)
# "main" as 2nd arg uses the working build (~/fifa_run.sh), "metal" the hybrid bbgpu build (~/fifa_metal/run.sh), default the side build (~/fifa_perf.sh).
MODE="${1:-run}"; TARGET="${2:-perf}"
if [ "$TARGET" = main ]; then RUNNER="$HOME/fifa_run.sh"; RUNS="$HOME/fifa_runs"; CFG="$HOME/Library/Application Support/shadPS4/config.json";
elif [ "$TARGET" = metal ]; then RUNNER="$HOME/fifa_metal/run.sh"; RUNS="$HOME/fifa_metal/runs"; CFG="$HOME/Library/Application Support/shadPS4QtLauncher/versions/Custom-metal/user/config.json";
elif [ "$TARGET" = perfdbg ]; then RUNNER="$HOME/fifa_metal/perf_dbg.sh"; RUNS="$HOME/fifa_metal/perf_runs"; CFG="$HOME/Library/Application Support/shadPS4QtLauncher/versions/Custom-perf/user/config.json";
else RUNNER="$HOME/fifa_perf.sh"; RUNS="$HOME/fifa_perf_runs"; CFG="$HOME/Library/Application Support/shadPS4QtLauncher/versions/Custom-perf/user/config.json"; fi
AT="$HOME/fifa_perf/autotest"; OCR="$AT/ocr"
# keyboard -> PS4 pad mapping of shadPS4 (input_config/default.ini): cross=n circle=b triangle=c square=v options=enter
# dpad=arrows l3=x r3=m l1=q r1=u l2=e r2=o touchpad=space
keychar() { case "$1" in cross|n) echo '"n"';; circle|b) echo '"b"';; triangle|c) echo '"c"';; square|v) echo '"v"';; options|enter) echo '(ASCII character 13)';;
  up) echo '"w"';; down) echo '"s"';; left) echo '"a"';; right) echo '"d"';; l3|x) echo '"x"';; r3|m) echo '"m"';; l1|q) echo '"q"';; r1|u) echo '"u"';;
  l2|e) echo '"e"';; r2|o) echo '"o"';; touchpad|space) echo '" "';; *) echo "";; esac; }
# The emulator samples the keyboard when the game polls the pad, so a key must stay down for a few frames:
# key down, hold ~150 ms, key up. Menu navigation uses the left stick keys (w/a/s/d) which also move the cursor.
press() { local ch; ch=$(keychar "$1"); [ -z "$ch" ] && { echo "unknown key $1"; return 1; }
  pgrep -x shadps4 >/dev/null || { echo "emulator not running - key '$1' not sent"; return 1; }
  ensure_front || { echo "could not bring the emulator window to the front - key '$1' not sent"; return 1; }
  osascript -e 'tell application "System Events"' -e "key down $ch" -e "delay ${HOLD:-0.15}" -e "key up $ch" -e 'end tell' 2>&1 | grep -v "^$" | head -1; }
# Focus validation: activate the emulator, verify it really is the frontmost process; if not, bounce focus
# through Finder and try again (up to 3 times). Keys are only sent once the check passes.
# Split mode (SHAD_BBGPU_SPLIT=1): the native GPU host's window takes the keyboard (shadps4's is hidden).
# The metal target runs split by default (run.sh); SHAD_BBGPU_SPLIT=0 in the environment overrides.
[ "${2:-}" = metal ] && [ -z "${SHAD_BBGPU_SPLIT:-}" ] && export SHAD_BBGPU_SPLIT=1
KEY_PROC=shadps4; [ "${SHAD_BBGPU_SPLIT:-0}" = 1 ] && KEY_PROC=bbgpu-host-macos27
# The GPU host run from an app bundle (~/fifa_metal/host_app, direct presentation + Game Mode): its direct
# layer is black in window-level captures (System Events still names the process bbgpu-host-macos27).
bundle_host() { pgrep -f '\.app/Contents/MacOS/bbgpu-host' >/dev/null 2>&1; }
key_proc() { echo "$KEY_PROC"; }
ensure_front() {
  local i front proc
  proc=$(key_proc)
  for i in 1 2 3; do
    osascript -e "tell application \"System Events\" to set frontmost of process \"$proc\" to true" >/dev/null 2>&1
    sleep 0.3
    front=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)
    [ "$front" = "$proc" ] && return 0
    echo "focus check failed (front=$front), retrying" >&2
    osascript -e 'tell application "System Events" to set frontmost of process "Finder" to true' >/dev/null 2>&1
    sleep 0.3
  done
  return 1; }
latest_run() { ls -d "$RUNS"/*/ 2>/dev/null | sort | tail -1; }   # newest by name (timestamp), not mtime
# Disk hygiene: keep the 8 newest run folders, and strip screenshots from anything older than the 3 newest.
prune_runs() { ls -td "$RUNS"/*/ 2>/dev/null | tail -n +9 | xargs rm -rf 2>/dev/null
  for d in $(ls -td "$RUNS"/*/ 2>/dev/null | tail -n +4); do rm -rf "$d/shots" 2>/dev/null; done; }
set_filter() { python3 -c "import json,sys; p=sys.argv[1]; c=json.load(open(p)); c.setdefault('Log',{})['filter']=' '.join(sys.argv[2].split()); json.dump(c,open(p,'w'),indent=4)" "$CFG" "$1"; rm -f "$CFG.playmode"; }
wait_marker() { # $1 regex, $2 timeout s  -> prints seconds waited, returns 1 on timeout
  local log="$(latest_run)/emulator.log" t0=$(date +%s) t; case "$2" in ''|*[!0-9]*) set -- "$1" 120;; esac
  while :; do if grep -qE "$1" "$log" 2>/dev/null; then t=$(( $(date +%s) - t0 )); echo "$t"; return 0; fi
    t=$(( $(date +%s) - t0 )); [ "$t" -ge "$2" ] && { echo "$t"; return 1; }; sleep 1; done; }
fps_sample() { # OCR the counter in the newest screenshot; prints the FPS number or empty
  local s; s=$(ls -t "$(latest_run)/shots"/*.jpg 2>/dev/null | head -1); [ -z "$s" ] && return
  local w; w=$(sips -g pixelWidth "$s" 2>/dev/null | awk '/pixelWidth/{print $2}'); [ -z "$w" ] && w=2560
  "$OCR" "$s" $((w-560)) 0 560 140 2>/dev/null | grep -oE "[0-9]+ FPS" | grep -oE "^[0-9]+" | head -1; }
case "$MODE" in
  keys)
    pgrep -x shadps4 >/dev/null || { echo "start the emulator first"; exit 1; }
    echo "sending 'cross' (n) to shadps4 ..."; press cross && echo "ok - if nothing happened, allow your terminal app under System Settings > Privacy & Security > Accessibility" ;;
  learn)
    set_filter "Kernel.Fs:info Kernel.Pthread:info ${LOG_EXTRA:-} *:error"
    SHOT_EVERY=2 bash "$RUNNER" start >/dev/null; DIR=$(latest_run); echo "learning run: $DIR"
    echo "Navigate to a kick-off match and play ~20 s, then run: bash ~/fifa_autotest.sh stop"
    ( while kill -0 "$(cat "$DIR/pid")" 2>/dev/null; do sleep 1; done ) &
    ;;
  stop)
    bash "$RUNNER" stop >/dev/null; DIR=$(latest_run); set_filter ""
    { echo "timeline of $DIR (log-order markers):"; grep -nE "MainHubWidget.big|KickOffHub.big|TeamSelect|KitSelect|kit/kit_[0-9]+_0_0.rx3|Match kicker thread|bootflowintro|FluxHub" "$DIR/emulator.log" | sed -E 's/\x1b\[[0-9;]*m//g; s/\[[^]]*\] <[A-Za-z]+> \([^)]*\) [a-z_]+\.cpp:[0-9]+ //; s/open: path = //; s/ flags.*//' | awk '!s[substr($0,index($0,":")+1)]++' | head -30; echo; echo "screenshots: $(ls "$DIR/shots" | wc -l) in $DIR/shots"; } | tee "$DIR/timeline.txt" ;;
  run)
    SEQ="$AT/sequence.txt"; [ -f "$SEQ" ] || { echo "no $SEQ yet - do a 'learn' run first"; exit 1; }
    set_filter "Kernel.Fs:info Kernel.Pthread:info ${LOG_EXTRA:-} *:error"
    T_LAUNCH=$(date +%s); SHOT_EVERY=5 bash "$RUNNER" start >/dev/null; DIR=$(latest_run); REPORT="$DIR/report.txt"
    echo "run dir $DIR" | tee "$REPORT"
    while IFS= read -r line; do line="${line%%#*}"; eval "set -- $line" 2>/dev/null; [ -z "$1" ] && continue
      pgrep -x shadps4 >/dev/null || { echo "EMULATOR EXITED before step: $line" | tee -a "$REPORT"; grep -E "<Critical>|Unhandled" "$DIR/emulator.log" | sed -E 's/\x1b\[[0-9;]*m//g' | head -2 | tee -a "$REPORT"; break; }
      case "$1" in
        wait) t=$(wait_marker "$2" "${3:-120}") && echo "marker '$2' after ${t}s" | tee -a "$REPORT" || echo "TIMEOUT waiting '$2' (${t}s)" | tee -a "$REPORT" ;;
        key) n="${3:-1}"; d="${4:-0.8}"; for ((i=0;i<n;i++)); do press "$2"; sleep "$d"; done ;;
        sleep) sleep "$2" ;;
        mark) echo "$(( $(date +%s) - T_LAUNCH ))s since launch: $2" | tee -a "$REPORT" ;;
        measure) # measure FPS for N seconds: screenshots every 5 s -> OCR
          n="${2:-60}"; echo "measuring FPS for ${n}s" | tee -a "$REPORT"; vals=""; t0=$(date +%s)
          while [ $(( $(date +%s) - t0 )) -lt "$n" ]; do sleep 5; v=$(fps_sample); [ -n "$v" ] && vals="$vals $v"; done
          echo "FPS samples:$vals" | tee -a "$REPORT"; echo "$vals" | tr ' ' '\n' | grep -E '^[0-9]+$' | awk '{s+=$1;n++} END{if(n) printf "FPS avg %.1f over %d samples\n", s/n, n}' | tee -a "$REPORT" ;;
      esac
    done < "$SEQ"
    bash "$RUNNER" stop >/dev/null; set_filter ""; echo "done -> $REPORT" ;;
  drive) # screen-driven run: every few seconds read the screen and press what it asks for, until the match runs
    prune_runs
    set_filter "Kernel.Fs:info Kernel.Pthread:info ${LOG_EXTRA:-} *:error"
    T_LAUNCH=$(date +%s); SHOT_EVERY=0 bash "$RUNNER" start >/dev/null; DIR=$(latest_run); REPORT="$DIR/report.txt"; mkdir -p "$DIR/shots"
    echo "run dir $DIR (drive mode)" | tee "$REPORT"; LAST=""; STATE=boot; SAME=0; INMATCH_T=0
    while [ $(( $(date +%s) - T_LAUNCH )) -lt 900 ]; do
      pgrep -x shadps4 >/dev/null || { VERDICT=EXITED; echo "EMULATOR EXITED in state $STATE" | tee -a "$REPORT"; grep -E "<Critical>|Unhandled" "$DIR/emulator.log" | sed -E 's/\x1b\[[0-9;]*m//g' | head -2 | tee -a "$REPORT"; break; }
      S=$(bash "$0" shot $TARGET); TXT=$(~/fifa_perf/autotest/ocr "$S" 2>/dev/null | grep -v shadPS4 | tr '\n' '|'); T=$(( $(date +%s) - T_LAUNCH ))
      ACT=""
      case "$TXT" in
        *SIGNIN*|*"SIGN IN"*|*"|OK|"*|*"|OK"*) ACT="cross"; NEW=dialog_ok ;;   # EA online sign-in / info dialogs
        *"PRESS ANY BUTTON"*)            ACT="cross"; NEW=stadium_card ;;
        *"PRESS START"*|*"ESC TO PLAY"*) ACT="options"; NEW=loading_drill ;;
        *"MATCH PREVIEW"*|*"PLAY MATCH"*) ACT="cross"; NEW=match_preview ;;
        *"SIDE SELECT"*)                  ACT="cross"; NEW=side_select ;;
        *"READY!"*)                       ACT="cross"; NEW=kit_select_ready ;;
        *"ATT|MID|DEF"*)                  ACT="cross"; NEW=team_select ;;
        *"Sele"*"Back"*)                  ACT="cross"; NEW=kit_select ;;   # two-player kit screen (OCR: "Selert|O Back"); after team/side rules
        *"KICK OFF"*|*"ICK OFF"*|*"SKILL GAMES"*|*"CONTINUE CAREER"*|*"TOURNAMENT|"*) ACT="cross"; NEW=hub ;;   # hub (OCR often drops letters)
        *"PRESS"*"RE-C"*)                 ACT="cross"; NEW=hub_offline ;;
        *"PRESS"*)                        ACT="options"; NEW=title ;;
        *"Official FIFA licensed"*|*"Manufactured under license"*) ACT=""; NEW=legal ;;
      esac
      FPSV=$(echo "$TXT" | grep -oE "[0-9]+ FPS" | grep -oE "^[0-9]+" | head -1)
      [ -z "$FPSV" ] && FPSV=$(echo "$TXT" | grep -oE "FPS\|(GPU\|Frame Interval\|)?[0-9]+\.[0-9]+" | grep -oE "[0-9]+\.[0-9]+$" | head -1 | cut -d. -f1)
      if [ -z "$FPSV" ]; then FST=$(grep -a "\[FSTAT\]" "$DIR/emulator.log" 2>/dev/null | tail -1); [ -n "$FST" ] && FPSV=$(echo "$FST" | sed -E 's/.*fps=([0-9]+).*/\1/') && [ "$STATE" = in_match ] && echo "${T}s ${FST#*\] }" >> "$REPORT"; fi
      HUDV=$(echo "$TXT" | grep -oE "\|[0-9]+\.[0-9]+\|[0-9]+\. ?[0-9]+ms\|[0-9]+\. ?[0-9]+ms" | head -1 | tr -d ' ')
      if echo "$TXT" | grep -qE "\|[0-9]{2}:[0-9]{2} .*(BAR|RMA)|BAR.?[0-9].*RMA|(LALIGA|EA SPORTS)\|[0-9]{2}:[0-9]{2}\|"; then NEW=in_match; ACT=""; fi
      # 2026-11-09: the FIP scoreboard OCRs without the team names; the match clock plus the player
      # indicator ("7 V. VINI JR.", "PEDRI 8") identifies the match.
      if echo "$TXT" | grep -qE "\|[0-9]{2}:[0-9]{2}\|" && echo "$TXT" | grep -qE "[0-9]{1,2} [A-Z]\. [A-Z]|[A-Z]{3,} [0-9]{1,2}\|"; then NEW=in_match; ACT=""; fi
      [ -z "${NEW:-}" ] && NEW="$STATE"
      if [ "$NEW" != "$STATE" ]; then echo "${T}s: $STATE -> $NEW (fps=${FPSV:-?})" | tee -a "$REPORT"; STATE="$NEW"; SAME=0; else SAME=$((SAME+1)); fi
      # --- automatic health checks (every sample) ---
      # 1) stall: the picture has not changed for STALL_SECS (boot: 120 s) -> abort. 2) visuals: compare with the
      # known-good reference of this screen (refs/<state>.jpg from the perf build); 2 bad samples in a row -> abort.
      # Bad/stalled shots are kept as $DIR/BAD_*.jpg. REF_SAVE=1 (on the good build) records missing references.
      FP=$(python3 "$AT/imgcheck.py" fp "$S" 2>/dev/null); NOW=$(date +%s)
      if [ -n "${LASTFP:-}" ] && [ -n "$FP" ] && awk "BEGIN{exit !($(python3 "$AT/imgcheck.py" same "$LASTFP" "$FP") < ${FROZEN_DIFF:-2})}"; then
        FROZEN_T=${FROZEN_T:-$NOW}; LIM=${STALL_SECS:-60}; [ "$STATE" = boot ] && LIM=120
        if [ $(( NOW - FROZEN_T )) -ge "$LIM" ]; then cp "$S" "$DIR/BAD_stall_$STATE.jpg"; echo "${T}s: STALL - picture frozen for $(( NOW - FROZEN_T )) s in $STATE -> $DIR/BAD_stall_$STATE.jpg" | tee -a "$REPORT"; VERDICT=STALL; break; fi
      else FROZEN_T=""; fi
      LASTFP="$FP"
      # 3) stuck in a state that animates (drill/dialog): sample the emulator once and abort after STATE_MAX s
      if [ "$NEW" = "$STATE" ] && [ "$SAME" -eq 0 ]; then STATE_T=$NOW; fi; STATE_T=${STATE_T:-$NOW}
      if [ "$STATE" != in_match ] && [ "$STATE" != boot ] && [ $(( NOW - STATE_T )) -ge "${STATE_MAX:-150}" ]; then
        P=$(pgrep -f "shadps4" | head -1); [ -n "$P" ] && sample "$P" 5 -file "$DIR/stall_sample.txt" >/dev/null 2>&1
        cp "$S" "$DIR/BAD_stall_$STATE.jpg"; echo "${T}s: STALL - stuck in $STATE for $(( NOW - STATE_T )) s (sampled)" | tee -a "$REPORT"; VERDICT=STALL; break; fi
      REFN="$STATE"; [ "$STATE" = kit_select_ready ] && REFN=kit_select; REF="$AT/refs/$REFN.jpg"
      if [ "$SAME" -ge 1 ] || [ "$STATE" = in_match ]; then
        if [ "${REF_SAVE:-0}" = 1 ]; then
          [ ! -f "$REF" ] && { [ "$STATE" != in_match ] || { [ "$INMATCH_T" != 0 ] && [ $(( T - INMATCH_T )) -ge 10 ]; }; } && cp "$S" "$REF" && echo "${T}s: saved reference $REF" | tee -a "$REPORT"
        elif ! echo " ${VIS_STATES:-hub side_select team_select kit_select kit_select_ready match_preview loading_drill in_match} " | grep -q " $STATE "; then :
        elif [ ! -f "$REF" ] && { [ "$STATE" = loading_drill ] || [ "$STATE" = in_match ]; }; then
          # no reference for the 3D scenes yet: a mostly near-black stadium/pitch is the known failure
          VD=$(python3 "$AT/imgcheck.py" diff "$S" "$S" 2>/dev/null | sed -E 's/.* dark=([0-9.]+).*/\1/')
          if [ -n "$VD" ] && awk "BEGIN{exit !($VD > ${VIS_DARK_ABS:-0.40})}"; then
            BADN=$(( ${BADN:-0} + 1 )); echo "${T}s: visual check $STATE: dark=$VD (bad $BADN)" >> "$REPORT"
            if [ "$BADN" -ge 2 ]; then cp "$S" "$DIR/BAD_visual_$STATE.jpg"; echo "${T}s: VISUAL BAD in $STATE (dark=$VD) -> $DIR/BAD_visual_$STATE.jpg" | tee -a "$REPORT"; VERDICT=VISUAL_BAD; break; fi
          else BADN=0; fi
        elif [ -f "$REF" ]; then
          VC=$(python3 "$AT/imgcheck.py" diff "$REF" "$S" 2>/dev/null)
          VM=$(echo "$VC" | sed -E 's/.*mean=([0-9.]+).*/\1/'); VD=$(echo "$VC" | sed -E 's/.* dark=([0-9.]+).*/\1/'); VR=$(echo "$VC" | sed -E 's/.*refdark=([0-9.]+).*/\1/')
          VLIM=${VIS_MEAN:-25}; [ "$STATE" = in_match ] && VLIM=${VIS_MEAN_MATCH:-45}
          if [ -n "$VC" ] && awk "BEGIN{exit !($VM > $VLIM || $VD > $VR + ${VIS_DARK:-0.10})}"; then
            BADN=$(( ${BADN:-0} + 1 )); echo "${T}s: visual check $STATE: $VC (bad $BADN)" >> "$REPORT"
            if [ "$BADN" -ge 2 ]; then cp "$S" "$DIR/BAD_visual_$STATE.jpg"; echo "${T}s: VISUAL BAD in $STATE ($VC) -> $DIR/BAD_visual_$STATE.jpg" | tee -a "$REPORT"; VERDICT=VISUAL_BAD; break; fi
          else BADN=0; [ -n "$VC" ] && [ "${VIS_LOG:-0}" = 1 ] && echo "${T}s: visual ok $STATE: $VC" >> "$REPORT"; fi
        fi
      fi
      # STOP_AT=<state>: dwell there without input, log HUD values for DWELL_SAMPLES samples, then stop
      if { [ -n "${STOP_AT:-}" ] && [ "$STATE" = "$STOP_AT" ]; } || { [ -n "${STOP_WHEN:-}" ] && echo "$TXT" | grep -qE "$STOP_WHEN" && ! { [ -n "${STOP_UNLESS:-}" ] && echo "$TXT" | grep -qE "$STOP_UNLESS"; }; }; then
        DW=${DW:-0}; DW=$((DW+1)); [ -n "$HUDV" ] && echo "${T}s dwell $STATE hud fps|gpu|frame=$HUDV" | tee -a "$REPORT"
        if [ "$DW" -ge "${DWELL_SAMPLES:-8}" ]; then echo "dwell done at $STATE" | tee -a "$REPORT"; break; fi
        sleep 5; continue
      fi
      [ "${HUD_ALL:-0}" = 1 ] && [ "$STATE" != in_match ] && [ -n "$HUDV" ] && echo "${T}s hud $STATE fps|gpu|frame=$HUDV" >> "$REPORT"   # HUD_ALL=1: HUD values in every state (loading drill etc.)
      if [ "$STATE" = in_match ]; then
        [ "$INMATCH_T" = 0 ] && INMATCH_T=$T && echo "match running at ${T}s; sampling FPS for 60 s" | tee -a "$REPORT" && FPSS=""
        cp "$S" "$DIR/match_${T}.jpg" 2>/dev/null
        [ -n "$FPSV" ] && FPSS="$FPSS $FPSV"
        [ -n "$HUDV" ] && echo "${T}s hud fps|gpu|frame=$HUDV" >> "$REPORT"
        echo "${T}s|${TXT}" >> "$DIR/samples.txt"   # full on-screen text per sample (Metal HUD numbers land here when MTL_HUD_ENABLED=1)
        if [ $(( T - INMATCH_T )) -ge "${SAMPLE_SECS:-60}" ]; then echo "FPS samples:$FPSS" | tee -a "$REPORT"; echo "$FPSS" | tr ' ' '\n' | grep -E '^[0-9]+$' | awk '{s+=$1;n++} END{if(n) printf "FPS avg %.1f over %d samples\n", s/n, n}' | tee -a "$REPORT"; break; fi
      elif [ -n "$ACT" ]; then
        # only act if the screen is stable (seen twice) or it is an explicit prompt; re-press if nothing changes
        if [ "$SAME" -ge 1 ] || [ "$STATE" = title ] || [ "$STATE" = stadium_card ] || [ "$STATE" = loading_drill ]; then
          HOLD=0.4 press "$ACT" >/dev/null; echo "${T}s: pressed $ACT in $STATE" >> "$REPORT"; SAME=0
        fi
      fi
      if [ "$SAME" -ge "${NUDGE_AFTER:-3}" ] && [ "$STATE" != in_match ]; then   # ~12 s without change: nudge with cross, then circle
        echo "${T}s: no change in $STATE for $((SAME*4)) s+ (text: ${TXT:0:100}) - nudging" | tee -a "$REPORT"; HOLD=0.4 press cross >/dev/null; SAME=0; NUDGES=$((${NUDGES:-0}+1))
        [ "$NUDGES" -ge 3 ] && HOLD=0.4 press circle >/dev/null && NUDGES=0
      fi
      NEW=""; sleep "${CYCLE_SLEEP:-2}"
      # keep disk use small: only the newest 20 screenshots of this run are kept while driving
      ls -t "$DIR/shots"/*.jpg 2>/dev/null | tail -n +$(( ${KEEP_SHOTS:-20} + 1 )) | xargs rm -f 2>/dev/null
    done
    [ -z "${VERDICT:-}" ] && { [ "$INMATCH_T" != 0 ] && VERDICT=MATCH_OK || VERDICT="ENDED_IN_$STATE"; }
    echo "VERDICT: $VERDICT" | tee -a "$REPORT"
    bash "$RUNNER" stop >/dev/null; set_filter ""; echo "done -> $REPORT"; cat "$REPORT" ;;
  key)   # manual stepping: bash ~/fifa_autotest.sh key <name> [repeat] [delay]
    n="${3:-1}"; d="${4:-0.8}"; for ((i=0;i<n;i++)); do press "$2"; sleep "$d"; done ;;
  shot)  # immediate screenshot of the emulator window -> prints the path
    DIR=$(latest_run); F="$DIR/shots/manual_$(date +%H%M%S).jpg"; mkdir -p "$DIR/shots"
    WID=""; [ -f /tmp/fifa_winid.swift ] && WID=$(swift /tmp/fifa_winid.swift 2>/dev/null)
    # SHOT_FULL=1 (default when the GPU host runs from an .app bundle: direct presentation, a window-level
    # capture of the direct layer is black): capture the whole screen instead of the window.
    if [ "${SHOT_FULL:-$(bundle_host && echo 1 || echo 0)}" = "1" ]; then screencapture -x -t jpg "$F" 2>/dev/null;
    elif [ -n "$WID" ] && [ "$WID" != "0" ]; then screencapture -x -o -l "$WID" -t jpg "$F" 2>/dev/null; else screencapture -x -t jpg "$F"; fi; echo "$F" ;;
  fps)   # OCR the FPS counter of the newest screenshot
    fps_sample ;;
  markers) # log markers seen so far in the current run
    DIR=$(latest_run); grep -nE "MainHubWidget.big|KickOffHub.big|TeamSelect|KitSelect|kit/kit_[0-9]+_0_0.rx3|Match kicker thread|bootflowintro|FluxHub|MoviePlayer" "$DIR/emulator.log" | sed -E 's/\x1b\[[0-9;]*m//g; s/\[[^]]*\] <[A-Za-z]+> \([^)]*\) [a-z_]+\.cpp:[0-9]+ //; s/open: path = //; s/ flags.*//' | awk '!s[substr($0,index($0,":")+1)]++' | tail -15 ;;
  *) echo "usage: $0 {drive|learn|run|stop|keys|key|shot|fps|markers} [main]"; exit 1 ;;
esac
