#!/bin/zsh
# Runs FIFA 16 in shadPS4 with Metal API validation. Run this from Tabby/Terminal, NOT from inside Claude Code.
export MTL_DEBUG_LAYER=1 MTL_DEBUG_LAYER_ERROR_MODE=nslog MTL_DEBUG_LAYER_WARNING_MODE=nslog
cd "$HOME/Library/Application Support/shadPS4QtLauncher/versions/Pre-release"
./shadps4 --game "/Volumes/SanDiskSSD/F16_02138_extracted/F16_02138/FIFA 16 - CUSA02138 + Update 1.07/FIFA_16/CUSA02138/eboot.bin" 2>&1 \
  | tee "/private/tmp/claude-501/-Volumes-SanDiskSSD-F16-02138-extracted-F16-02138-FIFA-16---CUSA02138---Update-1-07-FIFA-16-CUSA02138/dbbed053-17e5-4d95-b585-d31d29a90051/scratchpad/mtlval/run_full.txt" \
  | sed -E 's/\x1b\[[0-9;]*m//g' | grep -vE '^\[|^Skipped'
