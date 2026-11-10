import glob, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bc1, numpy as np
# usage: lv0.py <dir>: f48 BC1 images whose level 0 colour differs from level 1 (guest memory)
for d in sys.argv[1:]:
    n = bad = 0
    for f in sorted(glob.glob(d + '/*f48.raw.guest')):
        name = os.path.basename(f); p = name.split('_')
        if 'Bc1' not in name: continue
        w = int(p[4].split('x')[0])
        g = open(f, 'rb').read()
        s0 = (w // 4) ** 2 * 8; s1 = s0 // 4
        m0 = bc1.decode(g[:s0], w, w).reshape(-1, 3).mean(axis=0)
        m1 = bc1.decode(g[s0:s0 + s1], w // 2, w // 2).reshape(-1, 3).mean(axis=0)
        m2 = bc1.decode(g[s0 + s1:s0 + s1 + s1 // 4], w // 4, w // 4).reshape(-1, 3).mean(axis=0)
        n += 1
        # compare with level 2 as well: level 1 may be the red/blue swapped one in old runs
        if np.abs(m0 - m2).max() > 12:
            bad += 1
            print(d, p[2], p[3], w, 'lv0 %d %d %d lv1 %d %d %d lv2 %d %d %d' % (*m0, *m1, *m2))
    print(d, 'f48 images', n, 'level 0 unlike level 2:', bad)
