---
name: fifa16-app-mods-page
description: v0.4.0 FIFA 16.app Mods side menu - compiled fifamod engine in the bundle, Use mods switch, how to build and test it; warn before running tests on the user's screen
metadata:
  type: project
---

Mods live inside the app since 2026-11-06 (v0.4.0): side menu Game/Mods/Log, `Use mods` switch, Advanced Settings folds
the bundled items. Engine = compiled fifamod in `Contents/Resources/fifamod/engine` + 7zz; sources in worktree
`~/fifa_metal/app/engine` (branch app-engine of ~/FIFA16Mods, uncommitted). Build: `make_engine.sh`, then launcher swiftc,
then `make_mods_app.sh <ver>` (swaps files in out26, never rebuilds the emulator). SSD: "FIFA 16 v0.4.0.app".

**Why:** the user wants nobody to need the CLI, Python or Homebrew; mods optional.
**How to apply:** compile only with python.org Python (Homebrew dylibs have minos 27 and break macOS 26; make_engine.sh
asserts this). swiftc here has no @State macro plugin: keep view state in models. Tests: `FIFA16_DATA_DIR` for the app,
`work26/autotest_app.sh drive app` for matches.

The user watches the screen: a mods-off test match made them think their mods were gone. Say what is about to run on
their screen first. Related: [[fifa16-app-macos26-host]], [[fifamod-mod-manager]].
