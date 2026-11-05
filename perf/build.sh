#!/bin/zsh
# Builds the side (performance) emulator. Run from Tabby/Terminal.
set -e
export PATH="/opt/homebrew/opt/python@3.15/bin:/opt/homebrew/opt/llvm/bin:/opt/homebrew/bin:$PATH"
export HOMEBREW_NO_AUTO_UPDATE=1
cd "$HOME/fifa_perf/shadps4"
echo "source: $(git rev-parse --short HEAD) + $(git diff --stat | tail -1)"
[ -d build ] || cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64 -G Ninja 2>&1 | tail -2
cmake --build build --parallel 8 2>&1 | tee build.log | grep -E "error:|FAILED|Linking CXX executable" | tail -20
echo "BUILD EXIT: ${pipestatus[1]}"
ls -la build/shadps4 build/libvulkan_kosmickrisp.dylib 2>&1 | cut -c1-120
