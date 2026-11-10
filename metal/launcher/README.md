# FIFA 16 launcher (self-contained app)

A macOS launcher for FIFA 16 (PS4, CUSA02138) on the shadPS4 Metal hybrid build. Everything
except the game ships inside **F16.app**: the emulator, the Metal GPU library and its host
process, the runtime libraries, the launch logic and the mod manager. The user chooses four
folders in the launcher and presses Play. Modelled on the Bloodborne port's launcher: plain
`swiftc`, SwiftUI, an ad-hoc signed bundle, the icon made from the game's `sce_sys` artwork.

## The four folders

| folder | settings.json key | meaning |
|---|---|---|
| Game folder | `gameDir` | the dumped `CUSA02138` folder: `eboot.bin` and `sce_sys/param.sfo` inside. Required. |
| Update folder | `updateDir` | the dumped update 1.07 (`CUSA02138-UPDATE`): `eboot.bin` or `sce_sys/` inside. Optional: empty means the base 1.00 game runs. |
| Mods folder | `modsDir` | a patch / mods folder (what `fifamod` builds); the game sees it as `/download0`. Optional. |
| Savegame folder | `savesDir` | where savegames live. Empty means `<data dir>/saves`. |

Each row has **Choose…** (a folder picker); Update and Mods also have **Clear**. On first
launch, with no game folder set, the window says so and Play stays disabled.

## What Play does

Play runs `/bin/bash "F16.app/Contents/Resources/run.sh" <mode>` with these variables
added to the app's environment (PATH replaced by the login shell's PATH via `zsh -l`, LANG
`en_US.UTF-8` when missing, `__CFBundleIdentifier` removed):

```
FIFA_APP=<bundle path>           FIFA_DATA_DIR=~/Library/Application Support/FIFA 16
FIFA_GAME_DIR=<gameDir>          FIFA_UPDATE_DIR=<updateDir or empty>
FIFA_MODS_DIR=<modsDir or empty> FIFA_SAVES_DIR=<savesDir>
```

and, only when an option differs from run.sh's default: `BB_FULLSCREEN=0` (windowed),
`BB_PRESENT_MODE=Immediate` (low latency), `BB_VBLANK_HZ=120` (120 Hz mode), `BB_FRAME_STATS=1`, `MTL_HUD_ENABLED=1`. run.sh
sets every emulator and bridge variable itself; the launcher adds nothing else. run.sh prints
`run dir : <path>` and writes `<run dir>/pid`; the launcher keeps that pid in `state.json` and
**Stop** ends only that process (SIGTERM, SIGKILL after 10 s, then any `bbgpu-host*` child).
The game outlives the launcher unless asked; reopening the launcher shows Stop again.

Options (same meaning as before): Windowed / Full screen, Low-latency presentation, Frame stats
in the log, Metal Performance HUD, Launch mode Play / Diagnostics (`start`: full log plus the
screenshot and stats monitor). **Reset Options** restores run.sh's defaults and keeps the folders.

## Installation checklist

Required (Play needs all of them): Game folder, Savegame folder (exists or can be created, and
is writable), the bundled emulator, the bundled GPU host (`bbgpu-host-macos27`), the bundled
run.sh. Shown but never blocking: Update folder, Mods folder, Emulator config (`user/config.json`,
created on first Play), Shader cache (file count under `<savegame folder>/cache/CUSA02138`).

## Caches (0.5.1-i)

Nothing made from the game ships with the app. Two caches are built on the user's Mac from their own
game files and both live in `<savegame folder>/cache` (run.sh `place_caches` links the emulator's
`user/cache` there and moves a cache left by an older version):

- `CUSA02138/`: translated shaders and pipelines, filled while playing. The game shows a small
  "Building shaders" note while it compiles.
- `static_patches/`: the record of the code preparation done at the first start. While it is built
  (about 8 s) the game window shows a progress bar and the launcher's status line shows
  "First launch: preparing the game N%" (run.sh exports `BB_PROGRESS_FILE=<run dir>/progress`,
  content `prepare <0..1000>`; `LaunchProgress.read`).

The Savegame folder row shows the size ("Cache: 27 MB" or "Cache: empty") and a **Clear Cache…**
button with a confirmation. It removes the entries inside `<savegame folder>/cache` (and inside an
old unlinked `user/cache`), never the savegames, and is disabled while a game runs or the cache is
empty (`CacheStore` in Model/Status.swift). The next start prepares the game again.

## Where things are

```
F16.app/Contents/MacOS/F16                       the launcher (arm64)
F16.app/Contents/Resources/run.sh                    launch logic
F16.app/Contents/Resources/bbport.ini                renderer settings
F16.app/Contents/Resources/config.template.json      emulator config template
F16.app/Contents/Resources/emulator/shadps4          the emulator (x86-64) and its dylibs
F16.app/Contents/Resources/fifamod/fifamod.py        mod manager
F16.app/Contents/Helpers/FIFA 16 GPU.app             the GPU host app (bbgpu-host, -macos27, dylibs)

~/Library/Application Support/FIFA 16/                   data folder (everything writable)
  settings.json   the four folders and the options     state.json   pid of the game the launcher started
  user/           the emulator's user folder (config.json, log/; cache -> <savegame folder>/cache)
  runs/<timestamp>/emulator.log                          one folder per launch
  saves/          default savegame folder (savegames and cache/)
```

## Command line

```
"F16.app/Contents/MacOS/F16" --cli status             the checklist and the game's state
"F16.app/Contents/MacOS/F16" --cli env                the command and the variables Play adds
"F16.app/Contents/MacOS/F16" --cli set gameDir /path  settings from Terminal (keys: gameDir,
                                      updateDir, modsDir, savesDir, fullscreen, lowLatency, refresh120, frameStats, metalHUD, mode)
"F16.app/Contents/MacOS/F16" --cli play [--force]     refuses while another shadps4 runs unless forced
"F16.app/Contents/MacOS/F16" --cli stop
```

## Build and test

```
bash build.sh          # out/FIFA16Launcher and the bare F16.app (Info.plist, icon, launcher)
bash build.sh --test   # builds and runs Tests/main.swift first (PASS: n checks, or exit 1)
swift art/draw_icon.swift art/icon.png     # redraw the icon (checked in as art/icon.png)
```

Requirements: Xcode command line tools (`swiftc`, `sips`, `iconutil`, `codesign`). build.sh
produces only the skeleton; `make_app.sh` (in the tools repo) adds the payload, the GPU host app
and signs the finished bundle. The icon is the app's own drawing (`art/icon.png`); no game artwork
is bundled, the launcher reads the game's header art from the chosen game folder at runtime.

## Tests

`Tests/main.swift` runs against a throw-away data folder and a fake bundle (temp dirs with the
payload files, a game folder with `eboot.bin` and `sce_sys/param.sfo`, an update and a mods
folder); it never touches the real data folder or app. It checks settings defaults, round trip,
missing keys and `--cli set`; the checklist for every folder state; the exact environment Play
passes (golden table, default and every option); a launch through a stub run.sh that records
the environment it got; Stop against throw-away processes (wrong name refused, children
cleaned); `ps` parsing, the log tail and state.json.

## Mods (side menu)

The Mods page does everything the `fifamod` command line does, with nothing to install: the app
bundles the compiled engine (`Resources/fifamod/engine`, built by `~/fifa_metal/app/make_engine.sh`
with python.org's Python so every file loads on old macOS), `7zz` and the stock lists.
`Model/ModLibrary.swift` locates the library and runs the engine; `App/ModsModel.swift` and
`App/ModsView.swift` are the page. Mods are optional: the `Use mods` switch (also on the Mods
folder row) makes Play pass no overlay, and run.sh then points the `-mods` lookup at an empty
folder. The registry and merged tree stay on APFS in the data folder (`mods/`); the Mods folder can
be anywhere, or be an existing fifamod store (used in place) or a ready-made patch.
`FIFA16_DATA_DIR=<folder>` runs the app against a separate data folder for testing. This
toolchain's swiftc has no SwiftUI macro plugin: no `@State`; view state lives in the models.
`FIFA_TEST_ENGINE=<work_mods/pkg/fifamod> bash build.sh --test` also drives the real engine.
