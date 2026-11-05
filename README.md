# FIFA 16 (PS4) on shadPS4 / macOS - scripts, patches and notes

Everything around running FIFA 16 (CUSA02138 + 1.07) with the FIFA Infinity Patch in shadPS4 on an
Apple Silicon Mac. Code lives in sibling repos; this one holds the glue, launch/test scripts and notes.

| folder | what | original location |
|---|---|---|
| `metal/` | Metal hybrid runner (`run.sh`), ball/texture/mesh fixers, autotest helpers, `PLAN.md`, `bbport.ini`, launcher app sources, GPU host app wrapper | `~/fifa_metal/` |
| `perf/` | Vulkan side build scripts, side-changes patch, autotest OCR helpers | `~/fifa_perf/` |
| `home/` | `fifa_run.sh`, `fifa_perf.sh`, `fifa_overlay.sh`, `fifa_autotest.sh`, build/install helpers | `~/` |
| `skill/` | Claude Code skill: installing PC patches on the PS4 game (formats, Lua fixes, emulator notes, BIG4 reader) | `~/.claude/skills/fifa-pc-patch-on-ps4/` |
| `notes/` | project memory notes (setup, hybrid renderer history, fifamod, lessons) | Claude project memory |

Related repos: `fifa16-mods` (fifamod mod manager + PS4 asset fixers), `shadps4-fifa` (emulator
branches `metal-hybrid` and `rain-probe`), `bloodborne_mac_port-fifa` (branch `fifa-hybrid`, the
Metal GPU library). Game data, the FIP patch and mod content are not in any repo.
