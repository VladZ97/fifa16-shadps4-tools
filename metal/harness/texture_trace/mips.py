import sys, glob, os, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bc1
# usage: mips.py <dir> : per .guest BC1 image, mean RGB of each mip level and whether R/B alternate
d = sys.argv[1]
bad = good = 0
for f in sorted(glob.glob(d + '/*f48.raw.guest')):
    name = os.path.basename(f)
    parts = name.split('_')
    dim = [p for p in parts if 'x' in p and p[0].isdigit()][0]
    w, h = int(dim.split('x')[0]), int(dim.split('x')[1])
    if 'Bc1' not in name:
        continue
    raw = open(f, 'rb').read()
    off = 0
    means = []
    for l in range(6):
        lw, lh = max(w >> l, 4), max(h >> l, 4)
        size = (lw // 4) * (lh // 4) * 8
        if off + size > len(raw):
            break
        img = bc1.decode(raw[off:off + size], lw, lh)
        means.append(img.reshape(-1, 3).mean(axis=0))
        off += size
    if len(means) < 2 or means[0].sum() < 3:
        continue
    # swapped odd level: level l red ~ level 0 blue while level 0 red != blue
    m0 = means[0]
    if abs(m0[0] - m0[2]) < 8:
        continue
    sw = [abs(m[0] - m0[2]) + abs(m[2] - m0[0]) < abs(m[0] - m0[0]) + abs(m[2] - m0[2]) for m in means]
    if any(sw):
        bad += 1
    else:
        good += 1
    if len(sys.argv) > 2:
        print(name[:44], ' '.join('%d/%d/%d%s' % (m[0], m[1], m[2], '*' if s else '') for m, s in zip(means, sw)))
print('images with a distinct red/blue: consistent', good, 'with swapped levels', bad)
