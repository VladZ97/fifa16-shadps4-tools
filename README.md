# FIFA 16 (PS4) on shadPS4 / macOS - scripts, patches and notes

Everything around running FIFA 16 (CUSA02138 + 1.07) with the FIFA Infinity Patch in shadPS4 on an
Apple Silicon Mac. Code lives in sibling repos; this one holds the glue, launch/test scripts and notes.

| folder | what | original location |
|---|---|---|
| `metal/` | Metal hybrid runner (`run.sh`), ball/texture/mesh fixers, autotest helpers, `PLAN.md`, `bbport.ini`, GPU host app wrapper | `~/fifa_metal/` |
| `metal/launcher/` | FIFA 16.app sources (SwiftUI, four-folder self-contained launcher, Mods side page driving the bundled engine), `build.sh --test` | `~/fifa_metal/launcher/` |
| `metal/app/` | `make_app.sh <version>`: assembles the self-contained FIFA 16.app (emulator, libbbgpu, host, run.sh, fifamod), fixes rpaths, signs, zips; `make_engine.sh` (compiled fifamod + 7zz + unrar), `make_mods_app.sh` (adds the engine), `make_host26_app.sh <ver> [base]` (adds the macOS 26 host layout: stub + libbbhost; `WITH_EMULATOR/WITH_LAUNCHER/WITH_ENGINE=1`); the bundled `run.sh`; `work26/` = the app test harness (`autotest_app.sh drive app`, `compare_apps.py` bundle diff) | `~/fifa_metal/app/` |
| `metal/build_host.sh`, `metal/build_host26.sh` | build the GPU host binaries: plain host and `-macos27` (pinned segments) with the SDK 12 platform stamp, and the macOS 26 pair `bbgpu-host-macos26` + `libbbhost.dylib` | `~/fifa_metal/` |
| `perf/` | Vulkan side build scripts, side-changes patch, autotest OCR helpers | `~/fifa_perf/` |
| `home/` | `fifa_run.sh`, `fifa_perf.sh`, `fifa_overlay.sh`, `fifa_autotest.sh`, build/install helpers | `~/` |
| `skill/` | Claude Code skill: installing PC patches on the PS4 game (formats, Lua fixes, emulator notes, BIG4 reader) | `~/.claude/skills/fifa-pc-patch-on-ps4/` |
| `notes/` | project memory notes (setup, hybrid renderer history, fifamod, lessons) | Claude project memory |

Related repos: `fifa16-mods` (fifamod mod manager + PS4 asset fixers), `shadps4-fifa` (emulator
branches `metal-hybrid` and `rain-probe`), `fifa_mac_port` (branch `fifa-hybrid`, the Metal GPU
library and host; its Releases carry the finished FIFA 16.app, currently v0.4.7). Game data, the FIP patch and mod content are not in any repo.
