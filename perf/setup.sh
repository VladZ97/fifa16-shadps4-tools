#!/bin/zsh
# Side environment for performance work. Clones shadPS4 at the same revision as the working build and
# applies the backed-up local changes. Run from Tabby/Terminal. Does not touch the working build.
set -e
export PATH="/opt/homebrew/bin:$PATH"
cd "$HOME/fifa_perf"
if [ ! -d shadps4/.git ]; then
  git clone --filter=blob:none https://github.com/shadps4-emu/shadPS4.git shadps4
fi
cd shadps4
git checkout -q 3eecea94ddaca360b19f4b800523b609a8b2ffcc
git submodule update --init --recursive --depth 1 2>&1 | tail -3
PATCH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/FIFA16-shadPS4-backup-2026-10-27/emulator/shadps4-local-changes.patch"
if git apply --check "$PATCH" 2>/dev/null; then git apply "$PATCH" && echo "working-build patches applied"; else echo "patches already applied or conflict:"; git apply --check "$PATCH" || true; fi
git diff --stat | tail -1
echo "SETUP DONE"
