---
name: fifa16-github-repos
description: Private GitHub repos (VladZ97) holding the FIFA 16 / shadPS4 project code, created 2026-11-06; which local tree pushes where, and what must never be pushed
metadata:
  type: reference
---

Created 2026-11-06 (all private, account VladZ97, https remote named `private` in the clones):
- https://github.com/VladZ97/fifa16-mods  <- ~/FIFA16Mods (fifamod.py, tools/, README; .gitignore
  excludes merged/, stock/data/sceneassets/ (extracted game assets), *.dylib)
- https://github.com/VladZ97/fifa16-shadps4-tools  <- assembled copy in ~/fifa16-shadps4-tools
  (metal/, perf/, home/ scripts, skill/, notes/ = memory snapshot); re-copy + commit to update
- https://github.com/VladZ97/shadps4-fifa  <- ~/fifa_metal/shadps4-metal branch metal-hybrid and
  ~/fifa_perf/shadps4 branch rain-probe (both blob:none partial clones of upstream: push in
  slices, scratchpad chunkpush.sh pattern, http.postBuffer 500 MB, HTTP/1.1)
- https://github.com/VladZ97/fifa_mac_port (renamed from bloodborne_mac_port-fifa 2026-11-06; README = full
  getting-started guide; Releases: v0.1.0 launcher only; v0.2.0 = self-contained bundle
  FIFA16-macOS-v0.2.0.zip (install.sh --game <dir>; emulator + libbbgpu + host + runtime dylibs + run.sh + fifamod),
  recipe in fifa16-shadps4-tools/release/make_bundle.sh); v0.3.0 (2026-11-06) = ONE self-contained FIFA 16.app:
  emulator+libbbgpu+host+dylibs inside, rpaths @executable_path, bundled run.sh, four folders chosen in the launcher
  (game/update/mods/saves) -> env FIFA_* -> SHAD_USER_DIR/SHAD_UPDATE_DIR/SHAD_MODS_DIR/SHAD_DOWNLOAD_DIR/SHAD_HOME_DIR
  (emulator commit 0f94446). Build: ~/fifa_metal/app/make_app.sh <ver> (launcher sources ~/fifa_metal/launcher,
  GAME_ART_DIR=<sce_sys> for the icon). Data dir ~/Library/Application Support/FIFA 16/. Installed copy in ~/Applications.  <- ~/fifa_metal/bloodborne_mac_port
  branches fifa-hybrid + master (was a shallow clone: `git fetch --unshallow origin` first)
- https://github.com/VladZ97/pes2fifa  <- ~/FIFA16Mods/tools/pes2fifa (also tracked inside fifa16-mods);
  update with `git subtree split --prefix=tools/pes2fifa -b tmp && git push <url> tmp:main`
Unrelated: VladZ97/fifa16-native is an older Rust project (Oct 2026), not this work.

**How to apply:** never push game data, the FIP patch, mod content or extracted stock assets.
Commit with `git add src/` in the shadPS4 trees (externals are symlinked, show as typechange).
