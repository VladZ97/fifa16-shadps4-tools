#!/bin/zsh
# Builds the patched KosmicKrisp Vulkan driver (x86_64) for shadPS4. Run from Tabby/Terminal.
set -e
export PATH="/opt/homebrew/opt/python@3.15/bin:/opt/homebrew/opt/llvm/bin:/opt/homebrew/bin:$PATH"
export HOMEBREW_NO_AUTO_UPDATE=1
cd "/private/tmp/claude-501/-Volumes-SanDiskSSD-F16-02138-extracted-F16-02138-FIFA-16---CUSA02138---Update-1-07-FIFA-16-CUSA02138/dbbed053-17e5-4d95-b585-d31d29a90051/scratchpad/build/wrapper"
echo "python3 -> $(command -v python3)  meson -> $(command -v meson)"
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64 2>&1 | tee build-configure.log | tail -3
cmake --build build -j8 2>&1 | tee build.log | grep -E "error|Error|warning: unused|Linking|Built target|\[[0-9]+/[0-9]+\]" | tail -40
echo "BUILD EXIT: ${pipestatus[1]}"
ls -la build/externals/mesa/build-target/src/kosmickrisp/vulkan/libvulkan_kosmickrisp.dylib
file build/externals/mesa/build-target/src/kosmickrisp/vulkan/libvulkan_kosmickrisp.dylib
