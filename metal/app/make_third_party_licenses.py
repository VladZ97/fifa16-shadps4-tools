#!/usr/bin/env python3
"""Collects the licence texts of the libraries that are compiled or statically linked into the F16.app
binaries (the shadps4 emulator and the libbbgpu renderer with its GPU hosts) into
licenses/THIRD-PARTY-LICENSES.txt, which the bundle scripts ship as Resources/Licenses/.

usage: make_third_party_licenses.py [emulator checkout] [renderer checkout]
Run it again whenever a submodule is updated or a library is added to either build."""
import os, sys

EMU = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/fifa_metal/shadps4-metal")
REN = os.path.expanduser(sys.argv[2] if len(sys.argv) > 2 else "~/fifa_metal/fifa16_mac_port")
E, R = EMU + "/externals/", REN + "/"

def tail_from(path, marker):
    text = open(path, errors="replace").read()
    return text[text.rindex(marker):]

def head_comment(path, first, last):
    lines = open(path, errors="replace").read().split("\n")[first - 1:last]
    return "\n".join(l.lstrip(" */") for l in lines)

# (name, where it is used, [licence files or (callable, args)])
LIBS = [
    ("Abseil", "emulator", [E + "abseil-cpp/LICENSE"]),
    ("AMD GCN register headers", "emulator, renderer", [(head_comment, (E + "gcn/include/gcn/si_ci_vi_merged_offset.h", 2, 24))]),
    ("Boost", "emulator", [E + "ext-boost/LICENSE_1_0.txt"]),
    ("CLI11", "emulator", [E + "CLI11/LICENSE"]),
    ("cpp-httplib", "emulator", [E + "cpp-httplib/LICENSE"]),
    ("date (Howard Hinnant)", "emulator", [E + "date/LICENSE.txt"]),
    ("Dear ImGui", "emulator, renderer", [E + "imgui/LICENSE.txt"]),
    ("DejaVu Sans font", "renderer", [R + "gpu/third_party/fonts/LICENSE-DejaVu.txt"]),
    ("Discord RPC", "emulator", [E + "discord-rpc/LICENSE"]),
    ("RapidJSON (in Discord RPC)", "emulator", [E + "discord-rpc/thirdparty/rapidjson/license.txt"]),
    ("dr_flac", "emulator", [(tail_from, (E + "dr_flac/dr_flac.h", "This software is available as a choice"))]),
    ("epoll-shim", "emulator", [E + "epoll-shim/LICENSE"]),
    ("fmt", "emulator, renderer", [E + "fmt/LICENSE"]),
    ("FreeType", "emulator", [E + "freetype/LICENSE.TXT", E + "freetype/docs/FTL.TXT"]),
    ("FSR 1 Vulkan port", "renderer", [R + "gpu/third_party/fsr-vulkan/LICENSE.txt", R + "gpu/third_party/fsr-vulkan/NOTICE.md"]),
    ("FXAA 3.11 (NVIDIA)", "renderer", [R + "gpu/third_party/fxaa/LICENSE.txt"]),
    ("half", "emulator, renderer", [E + "half/LICENSE.txt"]),
    ("hwinfo", "emulator", [E + "hwinfo/LICENSE"]),
    ("ImGuiFileDialog", "emulator", [E + "ImGuiFileDialog/LICENSE"]),
    ("JSON for Modern C++", "emulator", [E + "json/LICENSE.MIT"]),
    ("LibAtrac9", "emulator, renderer", [E + "LibAtrac9/LICENSE"]),
    ("libpng", "emulator", [E + "libpng/LICENSE"]),
    ("libusb", "emulator", [E + "libusb/COPYING"]),
    ("magic_enum", "emulator, renderer", [E + "magic_enum/LICENSE"]),
    ("minimp3", "emulator", [E + "minimp3/LICENSE"]),
    ("MiniUPnPc", "emulator", [E + "miniupnp/LICENSE"]),
    ("miniz", "emulator, renderer", [E + "miniz/LICENSE"]),
    ("OpenAL Soft", "emulator", [E + "openal-soft/COPYING", E + "openal-soft/BSD-3Clause", E + "openal-soft/LICENSE-pffft"]),
    ("Protocol Buffers", "emulator", [E + "protobuf/LICENSE", E + "protobuf/third_party/utf8_range/LICENSE"]),
    ("pugixml", "emulator", [E + "pugixml/LICENSE.md"]),
    ("RenderDoc API header", "emulator", [(head_comment, (E + "renderdoc/renderdoc_app.h", 2, 22))]),
    ("robin-map", "emulator, renderer", [E + "robin-map/LICENSE"]),
    ("SDL3 hidapi", "emulator", [E + "sdl3/src/hidapi/LICENSE-bsd.txt"]),
    ("sirit", "emulator, renderer", [E + "sirit/LICENSE.txt"]),
    ("SPIRV-Headers (in sirit)", "emulator, renderer", [E + "sirit/externals/SPIRV-Headers/LICENSE"]),
    ("spdlog", "emulator", [E + "spdlog/LICENSE"]),
    ("stb_image, stb_image_write", "emulator", [(tail_from, (E + "stb/stb_image.h", "This software is available under 2 licenses"))]),
    ("toml11", "emulator", [E + "toml11/LICENSE"]),
    ("Tracy", "emulator", [E + "tracy/LICENSE", E + "tracy/public/libbacktrace/LICENSE"]),
    ("Vulkan-Headers", "emulator, renderer", [E + "vulkan-headers/LICENSE.md"]),
    ("Vulkan Memory Allocator", "emulator", [E + "vma/LICENSE.txt"]),
    ("Xbyak", "emulator", [E + "xbyak/COPYRIGHT"]),
    ("xxHash", "emulator, renderer", [E + "xxhash/LICENSE"]),
    ("ZArchive", "emulator", [E + "zarchive/LICENSE"]),
    ("zlib-ng", "emulator", [E + "zlib-ng/LICENSE.md"]),
    ("Zstandard", "emulator", [E + "zstd/LICENSE"]),
    ("Zydis", "emulator", [E + "zydis/LICENSE"]),
    ("Zycore (in Zydis)", "emulator", [E + "zydis/dependencies/zycore/LICENSE"]),
]

out = ["F16.app - licences of the libraries compiled or statically linked into its binaries",
       "",
       "The emulator (Resources/emulator/shadps4) and the renderer (libbbgpu.dylib, libbbhost.dylib and the",
       "F16 GPU hosts) contain the libraries below. Their licences ask that the copyright notice and the",
       "licence text accompany binary copies: they are reproduced here from the source trees named in",
       "SOURCES.txt. Libraries shipped as separate files (FFmpeg, SDL3, the Vulkan loader, KosmicKrisp,",
       "SPIRV-Cross, 7-Zip, UnRAR, Python) have their own files in this folder. The emulator is built",
       "without the FDK AAC and LibreSSL libraries of upstream shadPS4.",
       "",
       "Contents: " + ", ".join(n for n, _, _ in LIBS) + ".", ""]
for name, where, files in LIBS:
    out += ["=" * 100, f"{name}    (in: {where})", "=" * 100, ""]
    for f in files:
        text = f[0](*f[1]) if isinstance(f, tuple) else open(f, errors="replace").read()
        out += [text.replace("\r\n", "\n").replace("\t", "    ").strip("\n"), ""]
dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "licenses", "THIRD-PARTY-LICENSES.txt")
open(dst, "w").write("\n".join(l.rstrip() for l in "\n".join(out).split("\n")) + "\n")
print(f"{dst}: {len(LIBS)} libraries, {os.path.getsize(dst)} bytes")
