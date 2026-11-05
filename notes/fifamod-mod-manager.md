---
name: fifamod-mod-manager
description: "fifamod CLI (built 2026-11-04) manages FIFA 16 mods one-per-folder and builds the shadPS4 download overlay as a symlink tree; where it lives, exFAT caveats"
metadata:
  node_type: memory
  type: project
  originSessionId: 66775ac4-9d64-48d4-b1d5-cced44d51fd2
  modified: 2026-11-04T19:11:15.828Z
---

Since 2026-11-04 the shadPS4 `/download0` overlay for CUSA02138 is built by `fifamod`
(`~/FIFA16Mods/fifamod.py`, launcher `/opt/homebrew/bin/fifamod`, README beside it).
`download/CUSA02138 -> ~/FIFA16Mods/merged` = base patch (`/Volumes/SanDiskSSD/Manual Install`)
+ enabled mods, one folder each in `/Volumes/SanDiskSSD/FIFA16Mods/mods/<slug>/files`
(game layout), registry `~/FIFA16Mods/mods.json` (order = priority, last wins).
Mods as of 2026-11-04 evening (order = priority): FIP Theme (menus), Lean Lua, Intro Skip (the three
were the extras of ~/fifa_perf/overlay/CUSA02138.fip), PS4 hair layout (all facepack hair) (6,768 converted meshes; FIXED the
"wild texture"/exploding-hair bug, verified 2026-11-04 22:40), UCL 25-26 Scoreboard, La Liga Scoreboard (both replace overlay set 9 =
overlay_90xx + overlayComponents_9; mutually exclusive, last wins). The Metal build's
`versions/Custom-metal/user/download/CUSA02138` is also linked (`fifamod link`). Loose fonts.txt
REPLACES the packed one: build seeds it from the stock 12 fonts or the UI crashes at the first scoreboard.
Per-competition scoreboards BUILT 2026-11-04 22:40: hook in sceKernelOpen (file_system.cpp, both
~/fifa_metal/shadps4-metal and ~/fifa_perf/shadps4, installed as Custom-metal/Custom-perf) remembers <comp>
from specifictournament_<team>_<comp>_<n>.rx3 (logged 'Scoreboard: competition N', warning level) and serves
download0/scoreboards/<comp>/<path> for overlays/overlaycomponents_*. `fifamod scoreboard <comp> <mod>` builds
those folders (mod need not be enabled). Ids: 53 = La Liga, 223 = UCL (FIP V9), 39 = MLS; the
cascade ends in specifictournament_0_0_0 so the hook ignores comp 0 (bug found 2026-11-04 22:50). Log line is
error-level so play mode shows it. Install over a running emulator with cp+mv (atomic), never cp alone.
Rule (2026-11-04 23:20, user wants it data-driven): hook reads home/away from crest/stadium/stadium_<home>_<comp>_<stadium>_<away>.dds
and scoreboards/teamleague.txt (tools/fifadb.py t3db reader: ints are value-rangelow); league ids need both teams in the
league, tournament ids (no league rows, e.g. 223) always apply. Both scoreboard mods disabled = FIP default elsewhere.
Crests (23:45): scoreboard mods' white DXT5 crests render blank on PS4 -> tools/dds_ps4.py converts to uncompressed
32-bit (fixer); hook also redirects imgassets/crest* per competition and resets on results/fluxhub/selectteam screens.
`fifamod exclude <mod> <folder>` exists. Career crash: 0xcdcdcdcd on ff_DLLLoading right after the STUBBED
sceKernelStopUnloadModule (process.cpp); Cause: LoadAndStartModule's FindByName returned the stale FootballCompEngzf.prx on reload.
Fix 2026-11-04 23:55 (both trees): sceKernelStopUnloadModule runs Module::Stop (DT_FINI) and sets module->retired
(FindByName skips it) so the next load maps a fresh copy; old mapping leaked on purpose. Untested.
23:50: FluxHub.big loads at HALF TIME -> never use it as match-over; now only the crest redirect resets (results/
selectteam/kickoffhub), the scoreboard competition persists until the next cascade. Ball regression: the old .fip
overlay linked 59 fixed ball meshes (fifa_side/ball_fixed + balls-highpoly) as SYMLINKS, which the real-file import
missed -> now mod "FIP balls (PS4 fixed meshes+textures)". Lesson: import symlinks whose target is outside the base.
2026-11-06 00:52 FREEZE (run 20261106_001759, samples saved there): after 3 career-engine reload cycles (retire path
worked: no crash) a career match froze while loading kits: 90_RenderThread blocked in guest PthreadMutex::Lock,
all game threads parked, GPU host CP idle; window occlusion events coincided but activating the window did not
resume. Suspects: residual state from retired FootballCompEng copies, or the known loading stall. Unresolved.

**Why:** the user wants each mod in its own directory and a list to manage them, without
touching the 224k-file FIP patch. Untouched base dirs are linked as whole directories, so a
rebuild takes under a second.

Hair physics (simhair) was a wrong lead: the engine never probes the second haircloth candidate.
fifamod runs asset fixers on install (`run_fixers`, tools/hair_ps4.py); `fifamod fix <mod>|base`.

**How to apply:** never run `fip_overlay.sh` again (it re-points the symlink at the bare
patch). New packs: `fifamod install <archive>` (`--dry-run` shows the path mapping). After
hand-editing patch/mod files run `fifamod build`. Keep the merged tree on APFS: the SSD's
exFAT (fskit) fakes symlinks with `._` AppleDouble files, and lists non-ASCII names in NFD
while storing NFC, so `rm` fails on them (delete via the NFC name). See
[[fifa16-shadps4-mac-setup]].
