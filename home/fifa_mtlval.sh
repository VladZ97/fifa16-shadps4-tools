#!/bin/zsh
# Runs FIFA 16 in shadPS4 with Metal API validation. Run this from Tabby/Terminal, NOT from inside Claude Code.
export MTL_DEBUG_LAYER=1 MTL_DEBUG_LAYER_ERROR_MODE=nslog MTL_DEBUG_LAYER_WARNING_MODE=nslog
cd "$HOME/Library/Application Support/shadPS4QtLauncher/versions/Pre-release"
./shadps4 --game "/Volumes/SanDiskSSD/F16_02138_extracted/F16_02138/FIFA 16 - CUSA02138 + Update 1.07/FIFA_16/CUSA02138/eboot.bin" 2>&1 \
  | tee "${FIFA_SCRATCH:?set FIFA_SCRATCH to the build scratch folder}/mtlval/run_full.txt" \
  | sed -E 's/\x1b\[[0-9;]*m//g' | grep -vE '^\[|^Skipped'
