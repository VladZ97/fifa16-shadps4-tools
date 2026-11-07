# Third-party software in FIFA 16.app

This app bundles the following open-source software. The licence texts are in this folder.
The sources of the forks built for this app:

| component | where in the bundle | licence | source |
|---|---|---|---|
| shadPS4 (fork, branch `metal-hybrid`) | `Resources/emulator/shadps4` | GPL-2.0-or-later | https://github.com/VladZ97/shadps4-fifa (upstream https://github.com/shadps4-emu/shadPS4) |
| bloodborne_mac_port (fork, branch `fifa-hybrid`): libbbgpu, the GPU host, libbbhost | `Resources/emulator/libbbgpu.dylib`, `Helpers/FIFA 16 GPU.app` | GPL-2.0-or-later | https://github.com/VladZ97/fifa16_mac_port (upstream https://github.com/Wooloomooloo2/bloodborne_mac_port) |
| launcher, run.sh, fifamod engine (this project's own code) | `MacOS/FIFA 16`, `Resources/run.sh`, `Resources/fifamod/engine` | see the repositories | https://github.com/VladZ97/fifa16-shadps4-tools, https://github.com/VladZ97/fifa16-mods |
| FFmpeg (libavcodec, libavformat, libavutil, libswscale, libswresample; built without `--enable-gpl`) | `Resources/emulator`, `Helpers/.../MacOS` | LGPL-2.1-or-later | https://ffmpeg.org |
| SDL3 | same | zlib | https://libsdl.org |
| Vulkan Loader | `Resources/emulator/libvulkan.dylib` | Apache-2.0 | https://github.com/KhronosGroup/Vulkan-Loader |
| KosmicKrisp (Mesa Vulkan-on-Metal driver) | `Resources/emulator/libvulkan_kosmickrisp.dylib` | MIT | https://gitlab.freedesktop.org/mesa/mesa |
| SPIRV-Cross (inside libbbgpu) | | Apache-2.0 | https://github.com/KhronosGroup/SPIRV-Cross |
| 7-Zip (7zz) | `Resources/fifamod/7zz` | LGPL-2.1 + unRAR restriction, BSD 3-clause | https://7-zip.org |
| UnRAR | `Resources/fifamod/unrar` | UnRAR licence (freeware, redistributable) | https://www.rarlab.com |
| Python 3.10 (python.org build) with OpenSSL 1.1 | `Resources/fifamod/engine/_internal` | PSF, OpenSSL/SSLeay | https://www.python.org |
| PyInstaller bootloader | `Resources/fifamod/engine/fifamod` | GPL-2.0 with the bootloader exception | https://pyinstaller.org |

Other libraries statically linked into libbbgpu (fmt, magic_enum, miniz, robin-map, xxHash, sirit,
imgui, half) carry their own permissive licences in the fifa16_mac_port tree under `gpu/third_party`
and `deps/src`.

No files of FIFA 16 itself, of the FIFA Infinity Patch or of any mod are included. FIFA is a
trademark of its owners; this app is an unofficial community project with no affiliation to
Electronic Arts.
