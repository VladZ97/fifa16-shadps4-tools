#!/bin/zsh
# Builds a patched shadPS4 (x86_64, SDL frontend) with: flip-IRQ race fix (upstream PR #5039) + optional
# texture upload logging (SHAD_LOG_IMAGES=1). Run from Tabby/Terminal, not inside Claude Code.
set -e
export PATH="/opt/homebrew/opt/python@3.15/bin:/opt/homebrew/opt/llvm/bin:/opt/homebrew/bin:$PATH"
export HOMEBREW_NO_AUTO_UPDATE=1
cd "${FIFA_SCRATCH:?set FIFA_SCRATCH to the build scratch folder}/build/shadps4"
echo "source: $(git rev-parse --short HEAD)  (main 3eecea9 + local patches)"
cmake --fresh -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64 2>&1 | tee build-configure.log | tail -3
cmake --build build --parallel 8 2>&1 | tee build.log | grep -E "error:|FAILED|Linking CXX executable|\[[0-9]+/[0-9]+\] Linking" | tail -20
echo "BUILD EXIT: ${pipestatus[1]}"
ls -la build/shadps4 build/libvulkan.dylib build/libvulkan_kosmickrisp.dylib build/kosmickrisp_mesa_icd.json 2>&1
file build/shadps4 | cut -c1-100
