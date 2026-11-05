# Coarse image checks for the autotest driver (python3 imgcheck.py ...).
#   fp <img>              print a 16x9 grayscale fingerprint (hex) - equal fingerprints = frozen picture
#   same <fpA> <fpB>      print the mean abs difference of two fingerprints (0..255)
#   diff <ref> <img>      compare against a reference shot on an 8x6 grid of mean RGB cells;
#                         prints "worst=<max cell diff> mean=<mean cell diff> cell=<col,row> dark=<fraction of near-black px> refdark=<same for the ref>"
# The HUD/FPS overlay sits in the top-left cell, which is ignored.
import sys
from PIL import Image

def load(p, size):
    im = Image.open(p).convert("RGB")
    w, h = im.size
    im = im.crop((0, int(h * 0.04), w, h))   # drop the window title bar strip
    return im.resize(size, Image.BOX)

cmd = sys.argv[1]
if cmd == "fp":
    im = load(sys.argv[2], (16, 9)).convert("L")
    print(bytes(im.getdata()).hex())
elif cmd == "same":
    a, b = bytes.fromhex(sys.argv[2]), bytes.fromhex(sys.argv[3])
    print("%.1f" % (sum(abs(x - y) for x, y in zip(a, b)) / max(1, len(a))))
elif cmd == "diff":
    W, H = 8, 6
    r, s = load(sys.argv[2], (W, H)), load(sys.argv[3], (W, H))
    worst, wc, tot = 0.0, (0, 0), 0.0
    for y in range(H):
        for x in range(W):
            if (x, y) == (0, 0):
                continue
            d = sum(abs(p - q) for p, q in zip(r.getpixel((x, y)), s.getpixel((x, y)))) / 3
            tot += d
            if d > worst:
                worst, wc = d, (x, y)
    def dark(p):
        full = load(p, (160, 90)).convert("L")
        return sum(1 for v in full.getdata() if v < 12) / (160 * 90)
    print("worst=%.0f mean=%.1f cell=%d,%d dark=%.2f refdark=%.2f" % (worst, tot / (W * H - 1), wc[0], wc[1], dark(sys.argv[3]), dark(sys.argv[2])))
