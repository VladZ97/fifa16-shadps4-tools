#!/bin/zsh
# Copies the rebuilt GPU host into the app bundle and re-signs the bundle ad hoc (an unsigned or
# stale bundle signature gets the host SIGKILLed during the handshake: "status 0x9").
A="$HOME/fifa_metal/host_app/F16 GPU.app"
cp ~/fifa_metal/bloodborne_mac_port/out/bbgpu-host ~/fifa_metal/bloodborne_mac_port/out/bbgpu-host-macos27 "$A/Contents/MacOS/" && codesign --force --deep -s - "$A" 2>/dev/null && echo "refreshed and re-signed $A/Contents/MacOS"
