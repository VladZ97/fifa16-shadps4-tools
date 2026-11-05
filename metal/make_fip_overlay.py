#!/usr/bin/env python3
"""make_fip_overlay.py <name> <theme>: builds ~/fifa_perf/overlay/CUSA02138.<name> = the full FIP patch
(symlinks into the Manual Install) with the FIP theme <theme> laid over it, the lean player.lua /
crowd.lua and the intro-skip nav from the leanlua overlay. The Manual Install is never modified."""
import os, sys, shutil
name, theme = sys.argv[1], sys.argv[2]
M = "/Volumes/SanDiskSSD/Manual Install"
LEAN = os.path.expanduser("~/fifa_perf/overlay/CUSA02138.leanlua")
O = os.path.expanduser(f"~/fifa_perf/overlay/CUSA02138.{name}")
if os.path.lexists(O):
    # only ever remove our own overlay dir (symlinks inside are not followed by rmtree)
    assert not os.path.islink(O)
    shutil.rmtree(O)
os.makedirs(O)
def link_entries(src_dir, dst_dir):
    for b in os.listdir(src_dir):
        if b.startswith("._"):
            continue
        os.symlink(os.path.join(src_dir, b), os.path.join(dst_dir, b))
link_entries(M, O)
def materialise(rel):
    p = os.path.join(O, rel)
    if os.path.islink(p):
        target = os.readlink(p)
        assert os.path.isdir(target), p
        os.unlink(p)
        os.mkdir(p)
        link_entries(target, p)
    elif not os.path.isdir(p):
        os.makedirs(p)
def place(src, rel):
    parts = rel.split("/")[:-1]
    acc = ""
    for part in parts:
        acc = f"{acc}/{part}" if acc else part
        materialise(acc)
        assert not os.path.islink(os.path.join(O, acc)), acc
    dst = os.path.join(O, rel)
    if os.path.lexists(dst):
        assert os.path.islink(dst) or os.path.isfile(dst), dst
        os.unlink(dst)  # unlinks the symlink itself, never the patch file
    shutil.copy2(src, dst)
n = 0
troot = os.path.join(M, "fip", "theme", theme)
for root, dirs, files in os.walk(troot):
    for f in files:
        if f.startswith("._") or f == "preview.png":
            continue
        full = os.path.join(root, f)
        place(full, os.path.relpath(full, troot))
        n += 1
print("theme files placed:", n)
for rel in ("data/fifarna/lua/assets/player.lua", "data/fifarna/lua/assets/crowd.lua", "data/ui/nav/bootcommonflow.nav"):
    place(os.path.join(LEAN, rel), rel)
real = sum(len(files) for _, _, files in os.walk(O))
print("overlay", O, "real files", real)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fix_ball_textures
fix_ball_textures.rewire(O)
import fix_ball_meshes
fix_ball_meshes.rewire(O)
import stripify_balls
stripify_balls.rewire(O)
# 2026-11-03: on the Metal (split) build the unmodified FIP high-poly meshes and textures play without the
# stack-check crash of the in-process Vulkan build (20028-vertex mesh tested), so the originals override the
# stripified / header-fixed copies above (those stay as the fallback for the Vulkan build).
import subprocess
subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ball_originals.py'),
                os.path.basename(O), '--textures-original'], check=True)
