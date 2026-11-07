# FIFA 16 (PS4) on shadPS4 / macOS - scripts, patches and notes

Everything around running FIFA 16 (CUSA02138 + 1.07) with the FIFA Infinity Patch in shadPS4 on an
Apple Silicon Mac. Code lives in sibling repos; this one holds the glue, launch/test scripts and notes.

| folder | what | original location |
|---|---|---|
| `metal/` | Metal hybrid runner (`run.sh`), ball/texture/mesh fixers, autotest helpers, `PLAN.md`, `bbport.ini`, GPU host app wrapper (`host_app/`, "F16 GPU.app") | `~/fifa_metal/` |
| `metal/launcher/` | F16.app sources (SwiftUI, four-folder self-contained launcher, Mods side page driving the bundled engine), `build.sh --test` | `~/fifa_metal/launcher/` |
| `metal/app/` | `make_app.sh <version>`: assembles the self-contained F16.app (emulator, libbbgpu, host, run.sh, fifamod), fixes rpaths, signs, zips; `make_engine.sh` (compiled fifamod + 7zz + unrar), `make_mods_app.sh` (adds the engine), `make_host26_app.sh <ver> [base]` (adds the macOS 26 host layout: stub + libbbhost; `WITH_EMULATOR/WITH_LAUNCHER/WITH_ENGINE=1`); the bundled `run.sh`; `work26/` = the app test harness (`autotest_app.sh drive app`, `compare_apps.py` bundle diff) | `~/fifa_metal/app/` |
| `metal/build_host.sh`, `metal/build_host26.sh` | build the GPU host binaries: plain host and `-macos27` (pinned segments) with the SDK 12 platform stamp, and the macOS 26 pair `bbgpu-host-macos26` + `libbbhost.dylib` | `~/fifa_metal/` |
| `perf/` | Vulkan side build scripts, side-changes patch, autotest OCR helpers | `~/fifa_perf/` |
| `home/` | `fifa_run.sh`, `fifa_perf.sh`, `fifa_overlay.sh`, `fifa_autotest.sh`, build/install helpers | `~/` |
| `skill/` | Claude Code skill: installing PC patches on the PS4 game (formats, Lua fixes, emulator notes, BIG4 reader) | `~/.claude/skills/fifa-pc-patch-on-ps4/` |

Related repos: `fifa16-mods` (fifamod mod manager + PS4 asset fixers), `shadps4-fifa` (emulator
branches `metal-hybrid` and `rain-probe`), `fifa16_mac_port` (branch `fifa-hybrid`, the Metal GPU
library and host; its Releases carry the finished F16.app, currently v0.4.7). Game data, the FIP patch and mod content are not in any repo.

## Legal

- Unofficial, non-commercial community project. Not affiliated with, endorsed or sponsored by
  Electronic Arts Inc., FIFA, Sony Interactive Entertainment Inc., Konami, the shadPS4 project or
  the authors of any patch or mod.
- No game files, firmware, keys, patch or mod content are included or linked. You need your own
  copy of FIFA 16 for PlayStation 4 (CUSA02138) as a folder dump; nothing here decrypts anything or
  explains how to dump a game.
- Mods and patches remain their authors' work. The tools change your local copy only; do not
  redistribute fixed or converted files, share the tools instead.
- FIFA is a registered trademark of the Fédération Internationale de Football Association. FIFA 16
  and EA SPORTS are trademarks or product names of Electronic Arts Inc. PlayStation and PS4 are
  trademarks of Sony Interactive Entertainment Inc. PES and eFootball are trademarks of Konami.
  Used only to say which software this project works with.
- No warranty: provided "as is" (GPL sections 11 and 12). Use at your own risk.
- Licence: GNU General Public License version 2 or (at your option) any later version (LICENSE).
