#!/usr/bin/env python3
"""fix_ball_textures.py [overlay-name]: FIP16 ball textures carry a texture-header section (0x6bd085dc) that
says 2048x2048 while the texel sections hold 1024x1024 data; the PS4 engine trusts the header section and the
ball shows the texture tiled small. In stock files the header entry equals the 16-byte header that opens each
texel section (0x7a0b60da), so the fix copies those 16 bytes over the entry. Fixed copies go to
/Volumes/SanDiskSSD/fifa_side/ball_fixed (the Manual Install is never modified); rewire() points an overlay's
data/sceneassets/ball at them."""
import os, sys, struct, shutil
M = "/Volumes/SanDiskSSD/Manual Install"
BALL = os.path.join(M, "data/sceneassets/ball")
FIXED = "/Volumes/SanDiskSSD/fifa_side/ball_fixed"
TEXHDR, TEXEL = 0x6bd085dc, 0x7a0b60da

def sections(b):
    assert b[:4] == b"RX3l", "not RX3"
    n = struct.unpack("<I", b[12:16])[0]
    return [struct.unpack("<IIII", b[16 + 16 * i:32 + 16 * i]) for i in range(n)]

def fixed_bytes(b):
    """return repaired file bytes, or None if the header already matches the texel sections"""
    secs = sections(b)
    hdr = [s for s in secs if s[0] == TEXHDR]
    tex = [s for s in secs if s[0] == TEXEL]
    if not hdr or not tex: return None
    hoff, hsz = hdr[0][1], hdr[0][2]
    count = struct.unpack("<I", b[hoff:hoff + 4])[0]
    if count != len(tex) or hsz < 16 + 16 * count: return None
    out = bytearray(b); changed = False
    for i, (_, toff, tsz, _) in enumerate(tex):
        own = b[toff:toff + 16]
        if struct.unpack("<I", own[:4])[0] != tsz: return None   # unknown layout, leave alone
        e = hoff + 16 + 16 * i
        if out[e:e + 16] != own:
            out[e:e + 16] = own; changed = True
    return bytes(out) if changed else None

def build_fixed():
    os.makedirs(FIXED, exist_ok=True)
    n_fixed = n_ok = 0
    for f in sorted(os.listdir(BALL)):
        if f.startswith("._") or not f.endswith("_textures.rx3"): continue
        dst = os.path.join(FIXED, f)
        src = os.path.join(BALL, f)
        if os.path.exists(dst) and os.path.getsize(dst) == os.path.getsize(src):
            n_fixed += 1; continue
        nb = fixed_bytes(open(src, "rb").read())
        if nb is None: n_ok += 1; continue
        open(dst, "wb").write(nb); n_fixed += 1
    print(f"ball textures: {n_fixed} fixed copies in {FIXED}, {n_ok} already consistent")

def rewire(O):
    """O = overlay root. Makes data/sceneassets and data/sceneassets/ball real dirs of per-entry symlinks and
    points every texture that has a fixed copy at it."""
    if not os.path.isdir(FIXED): print("no fixed ball textures, overlay unchanged"); return
    def materialise(p):
        if os.path.islink(p):
            target = os.readlink(p); assert os.path.isdir(target), p
            os.unlink(p); os.mkdir(p)
            for b in os.listdir(target):
                if not b.startswith("._"): os.symlink(os.path.join(target, b), os.path.join(p, b))
        assert os.path.isdir(p) and not os.path.islink(p), p
    sa = os.path.join(O, "data", "sceneassets"); materialise(sa)
    ball = os.path.join(sa, "ball"); materialise(ball)
    n = 0
    for f in os.listdir(FIXED):
        if f.startswith("._"): continue
        dst = os.path.join(ball, f)
        if os.path.lexists(dst):
            assert os.path.islink(dst), dst   # only ever replace a symlink, never a copied patch file
            os.unlink(dst)
        os.symlink(os.path.join(FIXED, f), dst); n += 1
    print(f"overlay {O}: {n} ball textures -> fixed copies")

if __name__ == "__main__":
    build_fixed()
    if len(sys.argv) > 1: rewire(os.path.expanduser(f"~/fifa_perf/overlay/CUSA02138.{sys.argv[1]}"))
