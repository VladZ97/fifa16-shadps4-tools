#!/usr/bin/env python3
"""fix_ball_meshes.py [overlay-name]: FIP16 ball meshes are PC files whose index section (0x5878f4) is a
triangle LIST (primitive section 0xd48d7880 = 4); the stock PS4 ball meshes are triangle STRIPS (= 6) and the
PS4 ball renderer draws strips, so a list comes out as slivers across the sphere and the texture looks tiled.
Converts every patch ball mesh into an equivalent strip (each triangle a,b,c becomes a,b,c,c,c,a_next so every
real triangle sits on an even strip position and keeps its winding) into /Volumes/SanDiskSSD/fifa_side/ball_fixed
and (rewire) points the overlay at the converted files. The Manual Install is never modified."""
import os, sys, struct
M = "/Volumes/SanDiskSSD/Manual Install"
BALL = os.path.join(M, "data/sceneassets/ball")
FIXED = "/Volumes/SanDiskSSD/fifa_side/ball_fixed"
IDX, PRIM = 0x5878f4, 0xd48d7880

def sections(b):
    assert b[:4] == b"RX3l"
    n = struct.unpack("<I", b[12:16])[0]
    return [list(struct.unpack("<IIII", b[16 + 16 * i:32 + 16 * i])) for i in range(n)]

def strip_bytes(b):
    secs = sections(b)
    prim = [s for s in secs if s[0] == PRIM]; idx = [s for s in secs if s[0] == IDX]
    if not prim or not idx: return None
    ptype = struct.unpack("<I", b[prim[0][1]:prim[0][1] + 4])[0]
    if ptype != 4: return None                       # already a strip (6) or unknown
    off, sz = idx[0][1], idx[0][2]
    size, count, isz, z = struct.unpack("<IIII", b[off:off + 16])
    assert isz == 2 and count % 3 == 0 and size == sz, (size, count, isz, sz)
    tris = struct.unpack(f"<{count}H", b[off + 16:off + 16 + 2 * count])
    out = []
    for i in range(0, count, 3):
        a, c, d = tris[i], tris[i + 1], tris[i + 2]
        nxt = tris[i + 3] if i + 3 < count else d
        out += [a, c, d, d, d, nxt]
    body = struct.pack(f"<{len(out)}H", *out)
    if len(body) % 16: body += b"\0" * (16 - len(body) % 16)
    new_sec = struct.pack("<IIII", 16 + len(body), len(out), 2, z) + body
    # rebuild the file: sections re-laid in their original order, offsets recomputed
    order = sorted(range(len(secs)), key=lambda i: secs[i][1])
    hdr_len = 16 + 16 * len(secs)
    payloads = []
    for i in order:
        sid, o, s, _ = secs[i]
        payloads.append((i, new_sec if sid == IDX else b[o:o + s]))
    pos = hdr_len; chunks = []
    for i, p in payloads:
        if pos % 16: pad = 16 - pos % 16; chunks.append(b"\0" * pad); pos += pad
        secs[i][1] = pos; secs[i][2] = len(p); chunks.append(p); pos += len(p)
    body_all = b"".join(chunks)
    head = b[:8] + struct.pack("<II", hdr_len + len(body_all), len(secs)) + b"".join(struct.pack("<IIII", *s) for s in secs)
    nb = bytearray(head + body_all)
    # primitive type -> strip
    p = [s for s in secs if s[0] == PRIM][0]; nb[p[1]:p[1] + 4] = struct.pack("<I", 6)
    # the 0x22b2be36 summary section repeats the index header (size, count, index size, 0): keep it in step
    m = [s for s in secs if s[0] == 0x22b2be36]
    if m and nb[m[0][1] + 16:m[0][1] + 32] == struct.pack("<IIII", size, count, isz, z):
        nb[m[0][1] + 16:m[0][1] + 32] = struct.pack("<IIII", 16 + len(body), len(out), 2, z)
    else: raise ValueError("unexpected 0x22b2be36 layout")
    return bytes(nb)

def build_fixed():
    os.makedirs(FIXED, exist_ok=True); n = k = 0
    for f in sorted(os.listdir(BALL)):
        if f.startswith("._") or not f.endswith(".rx3") or f.endswith("_textures.rx3"): continue
        nb = strip_bytes(open(os.path.join(BALL, f), "rb").read())
        if nb is None: k += 1; continue
        open(os.path.join(FIXED, f), "wb").write(nb); n += 1
    print(f"ball meshes: {n} converted to strips in {FIXED}, {k} left alone")

def rewire(O):
    ball = os.path.join(O, "data/sceneassets/ball"); assert os.path.isdir(ball) and not os.path.islink(ball), ball
    n = 0
    for f in os.listdir(FIXED):
        if f.startswith("._") or f.endswith("_textures.rx3"): continue
        dst = os.path.join(ball, f)
        if os.path.lexists(dst): assert os.path.islink(dst), dst; os.unlink(dst)
        os.symlink(os.path.join(FIXED, f), dst); n += 1
    print(f"overlay {O}: {n} ball meshes -> strip copies")

if __name__ == "__main__":
    build_fixed()
    if len(sys.argv) > 1: rewire(os.path.expanduser(f"~/fifa_perf/overlay/CUSA02138.{sys.argv[1]}"))
