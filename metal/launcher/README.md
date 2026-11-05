# FIFA 16 launcher (shadPS4 Metal hybrid build)

A macOS launcher for FIFA 16 (PS4, CUSA02138, update 1.07), modelled on the Bloodborne port's
launcher (`~/fifa_metal/bloodborne_mac_port/launcher`). It has the same layout (`Model/`, `App/`,
`Tests/`), uses the same toolchain (plain `swiftc`, SwiftUI, an ad-hoc signed bundle with the icon
made from the game's `sce_sys` artwork) and the same window style.

## How it starts the game

Play runs **`/bin/bash ~/fifa_metal/run.sh play`**, the command you would type in Terminal. The
launcher does not copy or re-implement the launch. run.sh still chooses the emulator, config,
overlay, run folder, log, BB_*/SHAD_* defaults and the `pkill` of an older instance. If you never
change a setting, the launcher passes no extra variables, so a launch from the app matches a
launch from Terminal.

The launcher's settings are the existing knobs and nothing else. Each one is passed to run.sh as an
environment variable only when it differs from run.sh's default:

| Setting | Variable | run.sh default |
|---|---|---|
| Window: Windowed / Full screen | `BB_FULLSCREEN=0` | `1` (full screen) |
| Frame stats in the log | `BB_FRAME_STATS=1` | unset |
| Metal Performance HUD | `MTL_HUD_ENABLED=1` | unset |
| Low-latency presentation (display sync off) | `BB_PRESENT_MODE=Immediate` | unset (off). Measured here: flip-to-screen 18 to 22 ms instead of 25 to 29 ms, but on a non-ProMotion display it can tear, which is why it is opt-in. |
| Launch mode: Play / Diagnostics | `run.sh play` / `run.sh start` | play |

These are stored in `~/fifa_metal/launcher/settings.json`. If the file is missing, each value is
run.sh's default. **Reset to run.sh Defaults** in the window restores them.

The base environment is the app's own, with three changes:
- PATH is replaced by your login shell's PATH (`zsh -l`), so `python3` resolves as it does in Terminal.
- LANG is set to `en_US.UTF-8` when it is missing.
- `__CFBundleIdentifier` is removed.

Any other run.sh knob (`SHAD_BBGPU_SPLIT`, `KK_FLAGS`, ...) that is already in the app's environment
passes through, just as it would from Terminal.

## Window

- **Installation status**: run.sh, the game eboot (taken from run.sh's `GAME`), the update folder,
  the patch overlay (where `Custom-metal/user/download/CUSA02138` points), the Metal build, the GPU
  host (taken from run.sh's `BB_GPU_HOST` default), config.json, bbport.ini and the shader cache.
  The required items must be present before Play is enabled.
- **GPU host app**: run.sh's default host is
  `~/fifa_metal/host_app/FIFA 16 GPU.app/Contents/MacOS/bbgpu-host`. The bundle gives Metal direct
  presentation and Game Mode, and the emulator itself runs the `-macos27` sibling on macOS 27.
  - Status requires `bbgpu-host-macos27` and `Contents/Info.plist` in the bundle.
  - If a copy in the bundle is older than the one in `~/fifa_metal/bloodborne_mac_port/out`, the
    status page shows a warning with a **Refresh host** button. The button runs
    `bash ~/fifa_metal/host_app/refresh.sh`.
  - The button is disabled while any emulator is running (yours or another run's), because a
    running host uses those files.
- **Patch overlay**: lists `~/fifa_perf/overlay/CUSA02138.*`. Choosing one asks first, then
  re-points the `download/CUSA02138` symlink. It never replaces a real folder. This is the only
  thing the launcher changes outside its own folder, and only when you pick a different overlay.
- **Play / Stop**: Play warns you if another shadps4 is running, because run.sh's `pkill -x shadps4`
  would stop it. Stop ends only the emulator this launcher started: the pid is kept in `state.json`
  and its name is checked before stopping. It sends SIGTERM (as `run.sh stop` does) and SIGKILL
  after 10 s. Then it stops any `bbgpu-host*` child that is still running, and the screenshot
  monitor in start mode. The game outlives the launcher, as it does with run.sh. On its next launch
  the launcher finds the game again and shows Stop.
- **Log page**: follows the current run's `emulator.log` (last 600 lines, colour codes removed) and
  shows run.sh's own output.
- **Folders**: Open Run Folder (the current or latest `~/fifa_metal/runs/<timestamp>`), All Runs, and
  Open Shader Cache (`Custom-metal/user/cache/CUSA02138`, which also holds `metal/pipelines.binaryarchive`).

## Build and run

```
bash ~/fifa_metal/launcher/build.sh          # builds ~/fifa_metal/launcher/FIFA 16.app
bash ~/fifa_metal/launcher/build.sh --test   # also builds and runs the model tests first
open ~/fifa_metal/launcher/FIFA\ 16.app       # or double-click it / keep it in the Dock
```

Requirements: Xcode command line tools (`swiftc`, `sips`, `iconutil`, `codesign`). The game drive
must be mounted for the icon and header art. Without it the app still builds, but has no icon.

Fallbacks and scripting:
- `FIFA 16.command`: double-click to run `bash ~/fifa_metal/run.sh play` in Terminal. It does not
  apply the launcher's settings.
- `"FIFA 16.app/Contents/MacOS/FIFA 16" --cli status|env|play [--force]|stop`: the same model code
  with no window.
  - `env` prints the variables the game process will get.
  - `play` refuses to run while another shadps4 is running, unless you add `--force`.

## Tests

`Tests/main.swift` (run with `build.sh --test`) checks the model against the real run.sh:

- It parses the real `~/fifa_metal/run.sh` and compares its `EMU/GAME/CFG/RUNS`, every `export`ed
  name and every bridge default (`SHAD_BBGPU ... BB_FULLSCREEN`; `BB_GPU_HOST` = the FIFA 16 GPU.app host) with the launcher's golden list.
- It runs a **copy of the real run.sh** in a throw-away home folder:
  - The "emulator" is a stub that records its environment, arguments and working folder.
  - `pkill` and `sleep` are stubbed. A check confirms run.sh's `pkill -x shadps4` reached the stub,
    so the copy cannot stop a real emulator.
  - The recorded game environment must equal the model's (`RunScript.gameEnvironment`) and a
    literal golden table. This is checked for:
    - the default settings
    - every launcher setting changed
    - run.sh's own knobs set in the environment (`KK_FLAGS=""`, `SHAD_READBACK_TILED=none`,
      `PERF_SUBMIT`, `MTL_VALIDATE`, `SIDE_GAME`, ...)
    - start mode
  - It also checks play mode's `Log.filter=*:error` edit, the `.playmode` marker, the run folder,
    the pid file, the config copy and the emulator command line.
- It also tests settings.json, the GPU host bundle check and stale-copy warning, overlay switching (in a fake home), the log tail, `ps` parsing, and
  Stop against throw-away processes. These cover the wrong-name refusal and the leftover-child
  cleanup.

If the other agent changes run.sh's defaults, the launcher still runs the new script. The test then
fails until `Model/RunScript.swift` is updated to match, which keeps the mirror honest.
