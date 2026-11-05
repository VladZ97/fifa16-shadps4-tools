# voldecode.py <dump.bin> [w h d]: per-slice means and corner texels of a raw RGBA8 volume (linear layout
# assumed), to tell an identity LUT from a graded one or a scrambled upload.
import sys
f = sys.argv[1]; w, h, d = (int(x) for x in sys.argv[2:5]) if len(sys.argv) >= 5 else (32, 32, 32)
b = open(f, 'rb').read(); bpt = len(b) // (w * h * d)
print(f, len(b), "bytes,", bpt, "B/texel")
per = w * h * bpt
means = [round(sum(b[z*per:(z+1)*per]) / per, 1) for z in range(d)]
print("slice means:", means)
def tex(x, y, z):
    o = (z * w * h + y * w + x) * bpt; return list(b[o:o+bpt])
for z in (0, d // 2, d - 1):
    print(" z%2d:" % z, " ".join("(%d,%d)=%s" % (x, y, tex(x, y, z)) for x, y in ((0, 0), (w-1, 0), (0, h-1), (w-1, h-1), (w//2, h//2))))
# identity check: expected R = x or z axis mapping; report which axis each channel follows
import itertools
def axis_of(ch):
    best = None
    for name, fn in (("x", lambda x,y,z: x), ("y", lambda x,y,z: y), ("z", lambda x,y,z: z)):
        err = 0; n = 0
        for x, y, z in itertools.product(range(0, w, max(1, w//4)), range(0, h, max(1, h//4)), range(0, d, max(1, d//4))):
            v = tex(x, y, z)[ch]; e = fn(x, y, z) * 255 / (w - 1); err += abs(v - e); n += 1
        if best is None or err / n < best[1]: best = (name, err / n)
    return best
print("channel axes (name, mean abs error):", [axis_of(c) for c in range(3)])
