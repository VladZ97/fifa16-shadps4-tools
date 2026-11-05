---
name: fifa-pc-patch-on-ps4
description: Install PC community patches for EA FIFA (FIFA Infinity Patch "FIP", Moddingway, face packs, kit packs, database/squad updates) onto the PS4 version of the game running in the shadPS4 emulator on macOS. Use this whenever the user mentions a FIFA patch, mod, face pack, kit pack, roster/database update, "Manual Install" folder, FIP Patch Manager, or asks whether a PC mod can run on the PS4 game in shadPS4, even if they do not say "install". Also use it to debug patch symptoms in the emulator such as headless players, cyan crowd blocks, missing textures, or wrong menus after a patch.
---

# FIFA PC patches on the PS4 game in shadPS4

The PS4 builds of FIFA 15/16/17 use the same Ignite engine, the same database format,
the same `.rx3`/`.dds` asset formats and the same Lua asset scripts as the PC builds.
Verified on FIFA 16 (CUSA02138 + 1.07): a kit `.rx3` extracted from the PS4 archives has
the identical section table and texture header as the PC patch's file, and PC kits render
correctly in the emulator. So PC patches work, with three caveats this skill handles:

1. The PC patch's Windows installer (FIP Patch Manager) must be replicated by hand.
2. Some assets the PC scripts request are generated or shipped separately (crowd kits,
   face packs), so you must add Lua fallbacks or extra packs.
3. Files must be placed where the PS4 engine actually looks, which differs from PC.

## How the PS4 engine finds loose files

The engine probes loose files before its `.big` archives, in this order:

- `/download0/<path>` for almost everything: `data/sceneassets/**`, `data/ui/**`,
  `data/fifarna/lua/**`, `data/loc/*`, `data/db/fifa_ng_db.db`, `data/teammanagement/*`.
- `/app0/<name>.ini` for root ini files only (`cl.ini`, `sku.ini`, `locale.ini`, ...).

shadPS4 maps them to:

- `/download0` -> `~/Library/Application Support/shadPS4/download/<TITLEID>/`
- `/app0` -> the game folder, with overlays `<game>-mods` > `<game>-UPDATE` > base.

Therefore: patch content goes under the download folder (a symlink to the patch folder on
an external drive is fine and avoids copying tens of GB), and root ini files go into a
`<TITLEID>-mods` folder next to the game folder. Confirm the probing paths for a new title
by grepping the emulator log for `Opening path /download0/` before relying on this.

## Procedure

Run `scripts/fip_overlay.sh` and `scripts/fip_apply.py` for the mechanical steps; read
the sections below for the judgement calls.

### 1. Inventory the patch

Look at the patch folder before touching anything. A FIP "Manual Install" looks like:

```
data/db, data/loc, data/sceneassets/*, data/ui/*, data/fifarna/lua/*, dlc/
fip/version/<variant>/   per-region database + competition data (manager "Apply version")
fip/versionassets/       flags, league logos, trophies, keyed by nation/league id
fip/theme/<name>/        menu theme (manager "Install theme")
fip/boots, fip/gkgloves  previews + assignment lists (manager boot/glove tools)
FIP Patch Manager.exe, FifaLibrary16.dll   Windows-only, not needed
```

`fip/version/applied.ini` names the variant the author last applied. Updates (V9.1, V9.2,
...) are archives containing `Manual Install/...` and must be extracted in version order
on top of the base. A readme inside the update states the order and which variant to
apply. Face packs extract into `data/sceneassets/{heads,hair,hairlod,faces,simplecloth}`.
Multi-part RAR archives need every part; `unrar` stops at a missing volume.

### 2. Prove asset compatibility with one file first

Before installing 40 GB, drop two or three kit files for teams in the next fixture into
`download/<TITLEID>/data/sceneassets/kit/` and play a match. New designs showing means the
texture format is compatible. If they come out scrambled, the platform stores texel data
differently and artwork needs converting; database, Lua and locale parts still work.

### 3. Install

`scripts/fip_overlay.sh <TITLEID> "<patch folder>" "<game folder>"` links the download
overlay to the patch folder (backing up whatever was there) and copies the patch's root
ini files into `<game>-mods/`.

`scripts/fip_apply.py` then replicates the Windows manager:

- `updates`: extract update archives in order into the patch folder.
- `version <variant>`: copy `fip/version/<variant>/` over the root, copy
  `fip/versionassets/` flags/logos, then apply the variant's `nationidswaps.ini` and
  `leagueidswaps.ini` (regional variants reuse nation and league ids, e.g. Israel in Peru's
  slot; the artwork must follow the swap in both directions or menus show the wrong flags),
  write `applied.ini`.
- `theme <name>`: copy `fip/theme/<name>/` over the root (skipping preview.png).
- `facepack <archive>`: extract face packs (their top folder is stripped).

It keeps every overwritten file under `fip/_overwritten_by_mac_apply/`. The decompiled
manager confirmed these are plain file copies; nothing is generated.

### 4. Run, then analyse what the patch asked for and could not get

Play a match with the patch active, then run
`scripts/fip_missing.py --log <emulator log> --game "<game folder>" --patch "<patch folder>"`.
It lists files requested through the overlay that exist neither in the patch nor inside
the PS4 archives. Ignore `specific*` names and most `shoe/kit/warmup/body` variants: those
are optional override probes the engine makes for every player. Act on:

- `heads/head_<id>_0.rx3` missing: that player is flagged for a real face in the database
  but no face pack has it. Fix by adding the face pack, or force a generic head: in
  `data/fifarna/lua/assets/player.lua` add a table lookup at the top of `getPlayerFace`
  returning 1 for those ids (see `references/lua-fixes.md`). Do it inside the function,
  because other scripts reset the `playerFace` table.
- `crowd/crowdkit_<team>_*.rx3` missing with cyan blocks in the stands: FIP's crowd script
  expects generated crowd kits. Append the stock game's fallback, the team's real kit
  textures, to `GetRMCrowdShirt` in `crowd.lua` (see `references/lua-fixes.md`).
- `data/ui/game/components/*.big` or theme assets missing: a theme was never applied.
- `shoelib/`, `gkglove/`, `tattoo/`: PC-only cosmetic features; harmless.
- A stack-protector crash (`stack_chk_fail`) on the render thread while a match loads:
  look for 16-byte placeholder `.rx3` files (an `RX3l` header with zero sections) in the
  patch, typically `simplecloth/simhair_*.rx3` from face packs. The PC build tolerates them;
  the PS4 build overflows a stack buffer. Delete them so the engine falls back to its
  archives: `find <patch>/data -type f -size -33c -name '*.rx3'`.
- Crash (`stack_chk_fail`, render thread) right after the "Match kicker thread" starts, only
  at some stadiums: Revolution Mod's `ball.lua`. Its `${GetRMBall(?,0)}` / `GetRMBall(?,1)`
  prefixes expand to 23 candidate files per ball instance; the PS4 build cannot take it.
  Remove the two prefixes from the `ballmesh` / `balltex` AddAsset lines (keep the rest of
  the script). Bisect method that found it: swap one Lua script at a time for the stock one
  from the `.big` archives, adding no-op stubs for functions other scripts borrow.
- A `stack_chk_fail` on the render thread at the first ball touch (kick-off, warm-up) that
  only happens with some competitions or balls: the patch ships high-poly ball meshes
  (`sceneassets/ball/*.rx3` with a vertex section 0x587aa1 of ~77 KB instead of ~11 KB).
  The PS4 build draws ball meshes as triangle strips (RX3 section 0xd48d7880 = 6; the PC
  files are triangle lists = 4); strips of up to 11522 indices / 3840 vertices played without a
  crash (stock maxima are 9094 / 3636), a 14706-index list crashed. Do NOT swap in a low-poly mesh: its UV layout differs from the
  patch's 12-panel atlases and the ball shows the texture as dozens of tiny splashes. Convert
  the list into a strip instead (`~/fifa_metal/stripify_balls.py`: greedy strip growing with
  degenerate joins and parity kept; a 2961-vertex ball becomes ~8400 indices). Meshes above the
  limits still need decimation. Also rewrite the texture header: patch `_textures.rx3` declare
  2048x2048 while holding 1024x1024 data (`fix_ball_textures.py` copies each texel section's
  own 16-byte header over the header-section entry, as stock files have it). Verify offline by
  software-rendering the mesh UVs over the decoded BC1 atlas before testing in game.
- Also check the patch's shirt fonts: if names vanish, swap the stock font ids back to the
  PS4 originals (extract with `scripts/big4.py`) before suspecting anything else.

- The high-poly ball `stack_chk_fail` is a crash of shadPS4's in-process Vulkan GPU thread, not of the
  game: with the GPU side out of process (the Metal split build, bbgpu-host) the unmodified FIP meshes
  play, up to a 20028-vertex triangle list. On the Vulkan build keep the strip/limit workaround.

Always keep the original of any edited script beside it as `<file>.orig-before-ps4-fix`,
and re-check the edits after each update, since updates overwrite scripts.

### 5. Verify

Capture frames of a match (the HUD, crowd, close-ups of new signings) and compare with the
previous run. Emulator settings that were already needed for the stock game are unchanged
by patches; if a patch run regresses visually, suspect script overrides first and bisect by
temporarily moving `data/fifarna` out of the overlay.

## Rollback

Delete the symlink in the emulator's download folder and restore the backup folder beside
it; delete `<game>-mods/`. The patch folder itself is only modified by `fip_apply.py` and
by the Lua edits, both of which keep originals.

## References

- `references/formats.md`: BIG4 archive layout, chunkzip/chunklzma containers, RX3
  section table, how to extract a stock asset for comparison (`scripts/big4.py`).
- `references/lua-fixes.md`: exact Lua edits for headless players and crowd kits, and how
  the engine's semicolon-separated candidate lists work.
- `references/emulator-notes.md`: shadPS4 overlay precedence, log lines to grep, and the
  config that made FIFA 16 playable on Apple Silicon (readbacks, mic, DMA).

## Mod manager (since 2026-11-04)

The download overlay is now built by `fifamod` (`~/FIFA16Mods/fifamod.py`, launcher
`/opt/homebrew/bin/fifamod`): `download/CUSA02138 -> ~/FIFA16Mods/merged`, a symlink tree
of the base patch (`/Volumes/SanDiskSSD/Manual Install`) plus enabled mods kept one per
folder in `/Volumes/SanDiskSSD/FIFA16Mods/mods/<slug>/files`. Do NOT run `fip_overlay.sh`
any more (it would re-point the symlink at the bare patch); install extra packs with
`fifamod install <archive>` and rebuild with `fifamod build` after editing patch files by
hand. The merged tree must stay on APFS: the SSD's exFAT (fskit) fakes symlinks with `._`
AppleDouble files and cannot delete non-ASCII filenames.
