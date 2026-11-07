# Third-party software in FIFA 16.app

This app bundles the following open-source software. The licence texts are in this folder.
The sources of the forks built for this app:

| component | where in the bundle | licence | source |
|---|---|---|---|
| shadPS4 (fork, branch `metal-hybrid`) | `Resources/emulator/shadps4` | GPL-2.0-or-later | https://github.com/VladZ97/shadps4-fifa (upstream https://github.com/shadps4-emu/shadPS4) |
| bloodborne_mac_port (fork, branch `fifa-hybrid`): libbbgpu, the GPU host, libbbhost | `Resources/emulator/libbbgpu.dylib`, `Helpers/FIFA 16 GPU.app` | GPL-2.0-or-later | https://github.com/VladZ97/fifa16_mac_port (upstream https://github.com/Wooloomooloo2/bloodborne_mac_port) |
| launcher, run.sh, fifamod engine (this project's own code) | `MacOS/FIFA 16`, `Resources/run.sh`, `Resources/fifamod/engine` | see the repositories | https://github.com/VladZ97/fifa16-shadps4-tools, https://github.com/VladZ97/fifa16-mods |
| FFmpeg n7.1.5 (libavcodec, libavformat, libavutil, libswscale, libswresample; built by fifa16_mac_port's `scripts/macos/bootstrap_deps.sh` without `--enable-gpl`) | `Resources/emulator`, `Helpers/.../MacOS` | LGPL-2.1-or-later | https://github.com/FFmpeg/FFmpeg/tree/n7.1.5 |
| SDL3 3.4.18 (built by the same bootstrap script) | same | zlib | https://github.com/libsdl-org/SDL |
| Vulkan Loader (built from shadps4-fifa's `externals/vulkan-loader`) | `Resources/emulator/libvulkan.dylib` | Apache-2.0 | https://github.com/KhronosGroup/Vulkan-Loader |
| KosmicKrisp (Mesa 27.0.0-devel, Vulkan-on-Metal driver; built from shadps4-fifa's `externals/mesa-kosmickrisp` submodule at `52d87b35`) | `Resources/emulator/libvulkan_kosmickrisp.dylib` | MIT | https://gitlab.freedesktop.org/mesa/mesa |
| SPIRV-Cross (inside libbbgpu) | | Apache-2.0 | https://github.com/KhronosGroup/SPIRV-Cross |
| 7-Zip 23.01 (7zz, unmodified Homebrew build) | `Resources/fifamod/7zz` | LGPL-2.1 + unRAR restriction, BSD 3-clause | https://7-zip.org/download.html (source 7z2301-src) |
| UnRAR 6.12 (unmodified Homebrew build) | `Resources/fifamod/unrar` | UnRAR licence (free distribution) | https://www.rarlab.com/rar_add.htm |
| Python 3.10.11 (python.org build; the ssl and hashlib modules and OpenSSL are excluded) | `Resources/fifamod/engine/_internal` | PSF-2.0 | https://www.python.org |
| PyInstaller bootloader (6.22.3) | `Resources/fifamod/engine/fifamod` | GPL-2.0-or-later with the bootloader exception | https://pyinstaller.org |

Other libraries statically linked into libbbgpu (fmt, magic_enum, miniz, robin-map, xxHash, sirit,
imgui, half) carry their own permissive licences in the fifa16_mac_port tree under `gpu/third_party`
and `deps/src`.

No files of FIFA 16 itself, of the FIFA Infinity Patch or of any mod are included.

## Legal

- Unofficial, non-commercial community project. Not affiliated with, endorsed or sponsored by
  Electronic Arts Inc., FIFA, Sony Interactive Entertainment Inc., Konami, the shadPS4 project or
  the authors of any patch or mod.
- You need your own copy of FIFA 16 for PlayStation 4 (CUSA02138) as a folder dump. This app does
  not decrypt anything and gives no instructions for dumping.
- Mods and patches remain their authors' work; the PS4 fixes change your local copy only. Do not
  redistribute fixed or converted files.
- FIFA is a registered trademark of the Fédération Internationale de Football Association. FIFA 16
  and EA SPORTS are trademarks or product names of Electronic Arts Inc. PlayStation and PS4 are
  trademarks of Sony Interactive Entertainment Inc. Used only to say which software this app works with.
- Offline play only. No warranty: provided "as is" (GPL sections 11 and 12); use at your own risk.
- The GPL parts are licensed under GPL version 2 or any later version; combined with the Apache-2.0
  components the binary as a whole may be used under GPL version 3. Corresponding source: SOURCES.txt
  (repositories and commits; each repository carries a tag named after the release).
