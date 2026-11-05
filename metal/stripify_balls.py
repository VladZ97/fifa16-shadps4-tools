#!/usr/bin/env python3
"""stripify_balls.py [overlay-name]: FIP16's real ball meshes (fip/_overwritten_by_mac_apply/balls-highpoly, PC
triangle lists of ~2960 vertices / 14706 indices) carry the UV layout that matches FIP's 12-panel ball atlases; the
low-poly meshes copied over them earlier have a different layout, so the atlas shows up as dozens of tiny splashes.
The PS4 build draws its ball meshes as triangle strips and tolerates up to ~9100 strip indices (stock maximum),
while a 14706-index list crashed it. This turns every high-poly list into one strip (greedy strip growing, joined
with degenerate indices, parity kept so winding survives), writes the result to
/Volumes/SanDiskSSD/fifa_side/ball_fixed/<name>.rx3 and (rewire) points the overlay at it."""
import os, sys, struct, collections
M = "/Volumes/SanDiskSSD/Manual Install"
HP = os.path.join(M, "fip/_overwritten_by_mac_apply/balls-highpoly")
FIXED = "/Volumes/SanDiskSSD/fifa_side/ball_hp"
MAX_IDX, MAX_VERTS = 11522, 3872   # tested in game (ball_160: 3840 verts / 11522 indices played a full match); bigger meshes keep the low-poly strip
IDX, PRIM, SUMMARY = 0x5878f4, 0xd48d7880, 0x22b2be36

def sections(b):
    assert b[:4] == b"RX3l"
    n = struct.unpack("<I", b[12:16])[0]
    return [list(struct.unpack("<IIII", b[16 + 16 * i:32 + 16 * i])) for i in range(n)]

def stripify(tris):
    """tris: list of (a,b,c). One strip drawing every triangle once with its winding. Greedy: start at
    triangles with the fewest free neighbours, try the three rotations, grow forward and backward, keep the
    longest; strips are joined with degenerate indices and parity padding."""
    edge_tris = collections.defaultdict(list)
    for t, (a, b, c) in enumerate(tris):
        for e in ((a, b), (b, c), (c, a)):
            edge_tris[frozenset(e)].append(t)
    used = [False] * len(tris)
    def free_neighbours(t):
        a, b, c = tris[t]
        return sum(1 for e in ((a, b), (b, c), (c, a)) for u in edge_tris[frozenset(e)] if u != t and not used[u])
    def across(p, q, taken):
        """unused triangle containing directed edge (p,q) in its winding; returns (t, third)"""
        for u in edge_tris[frozenset((p, q))]:
            if used[u] or u in taken: continue
            v = tris[u]
            for i in range(3):
                if (v[i], v[(i + 1) % 3]) == (p, q): return u, v[(i + 2) % 3]
        return None
    def grow(strip, taken):
        while True:
            n = len(strip); p, q = strip[-2], strip[-1]
            want = (q, p) if (n - 2) % 2 == 1 else (p, q)
            r = across(*want, taken)
            if r is None: return
            taken.add(r[0]); strip.append(r[1])
    def build(start, rot):
        v = tris[start]; a, b, c = v[rot], v[(rot + 1) % 3], v[(rot + 2) % 3]
        taken = {start}; strip = [a, b, c]; grow(strip, taken)
        # backward: reverse (winding of a reversed strip is kept when its length is odd)
        rev = strip[::-1]
        if len(rev) % 2 == 1: rev = [rev[0]] + rev   # a reversed strip keeps its winding only at even length
        grow(rev, taken)
        return rev, taken
    strips = []
    order = sorted(range(len(tris)), key=free_neighbours)
    for start in order:
        if used[start]: continue
        best = None
        for rot in range(3):
            strip, taken = build(start, rot)
            if best is None or len(taken) > len(best[1]): best = (strip, taken)
        for t in best[1]: used[t] = True
        strips.append(best[0])
    out = []
    for s in strips:
        if not out: out += s; continue
        out += [out[-1], s[0]]
        if len(out) % 2: out.append(s[0])
        out += s
    return out, len(strips)

def check(strip, tris):
    real = []
    for k in range(len(strip) - 2):
        a, b, c = strip[k:k + 3]
        if len({a, b, c}) < 3: continue
        real.append((a, b, c) if k % 2 == 0 else (b, a, c))
    def canon(t): 
        i = t.index(min(t)); return (t[i], t[(i + 1) % 3], t[(i + 2) % 3])
    return sorted(canon(t) for t in real) == sorted(canon(tuple(t)) for t in tris)

def convert(b):
    secs = sections(b)
    prim = [s for s in secs if s[0] == PRIM][0]; isec = [s for s in secs if s[0] == IDX][0]
    ptype = struct.unpack("<I", b[prim[1]:prim[1] + 4])[0]
    if ptype != 4: return None, 0
    off = isec[1]; size, count, isz, z = struct.unpack("<IIII", b[off:off + 16])
    assert isz == 2 and count % 3 == 0 and size == isec[2]
    flat = struct.unpack(f"<{count}H", b[off + 16:off + 16 + 2 * count])
    tris = [flat[i:i + 3] for i in range(0, count, 3)]
    strip, nstrips = stripify(tris)
    assert check(strip, tris), "strip does not reproduce the triangles"
    body = struct.pack(f"<{len(strip)}H", *strip)
    if len(body) % 16: body += b"\0" * (16 - len(body) % 16)
    new_sec = struct.pack("<IIII", 16 + len(body), len(strip), 2, z) + body
    order = sorted(range(len(secs)), key=lambda i: secs[i][1]); hdr_len = 16 + 16 * len(secs)
    pos = hdr_len; chunks = []
    for i in order:
        sid, o, s, _ = secs[i]; p = new_sec if sid == IDX else b[o:o + s]
        if pos % 16: pad = 16 - pos % 16; chunks.append(b"\0" * pad); pos += pad
        secs[i][1] = pos; secs[i][2] = len(p); chunks.append(p); pos += len(p)
    body_all = b"".join(chunks)
    nb = bytearray(b[:8] + struct.pack("<II", hdr_len + len(body_all), len(secs)) + b"".join(struct.pack("<IIII", *s) for s in secs) + body_all)
    p = [s for s in secs if s[0] == PRIM][0]; nb[p[1]:p[1] + 4] = struct.pack("<I", 6)
    m = [s for s in secs if s[0] == SUMMARY][0]
    assert nb[m[1] + 16:m[1] + 32] == struct.pack("<IIII", size, count, isz, z)
    nb[m[1] + 16:m[1] + 32] = struct.pack("<IIII", 16 + len(body), len(strip), 2, z)
    return bytes(nb), len(strip)

def build_fixed(only=None):
    os.makedirs(FIXED, exist_ok=True); worst = 0; n = 0
    for f in sorted(os.listdir(HP)):
        if f.startswith("._") or not f.endswith(".rx3"): continue
        if only and f not in only: continue
        nb, cnt = convert(open(os.path.join(HP, f), "rb").read())
        if nb is None: continue
        open(os.path.join(FIXED, f), "wb").write(nb); n += 1; worst = max(worst, cnt)
    print(f"high-poly meshes stripified: {n}, largest strip {worst} indices (stock maximum 9094)")

def fits(path):
    b = open(path, "rb").read(); secs = sections(b)
    i = [x for x in secs if x[0] == IDX][0]; v = [x for x in secs if x[0] == 0x587aa1][0]
    return struct.unpack("<I", b[i[1] + 4:i[1] + 8])[0] <= MAX_IDX and struct.unpack("<I", b[v[1] + 4:v[1] + 8])[0] <= MAX_VERTS

def rewire(O):
    ball = os.path.join(O, "data/sceneassets/ball"); assert os.path.isdir(ball) and not os.path.islink(ball), ball
    n = skipped = 0
    for f in sorted(os.listdir(FIXED)):
        if f.startswith("._") or not f.endswith(".rx3"): continue
        if not fits(os.path.join(FIXED, f)): skipped += 1; continue
        dst = os.path.join(ball, f)
        if os.path.lexists(dst): assert os.path.islink(dst), dst; os.unlink(dst)
        os.symlink(os.path.join(FIXED, f), dst); n += 1
    print(f"overlay {O}: {n} ball meshes -> stripified high-poly, {skipped} too big (low-poly strip kept)")

if __name__ == "__main__":
    only = set(a for a in sys.argv[2:]) or None
    build_fixed(only)
    if len(sys.argv) > 1 and sys.argv[1] != "-": rewire(os.path.expanduser(f"~/fifa_perf/overlay/CUSA02138.{sys.argv[1]}"))
