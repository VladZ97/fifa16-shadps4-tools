import glob, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bc1, numpy as np, re
# usage: lv0gpu.py <dir>...: per f48 BC1 image, mean colour of level 0 on the GPU (.raw), level 0 and level 2 in guest memory
for d in sys.argv[1:]:
    n = badg = badm = 0
    for f in sorted(glob.glob(d + '/*_f4[8a].raw.guest')):
        name = os.path.basename(f); p = name.split('_')
        if 'Bc1' not in name: continue
        m = re.search(r'_([0-9a-f]+)_(\d+)x\d+x\d+_', name); w = int(m.group(2)); p = [0, name.split('_')[0] + ' ' + (name.split('_')[2] if name.startswith('bind') else ''), m.group(1)]
        g = open(f, 'rb').read()
        r = open(f[:-6], 'rb').read() if os.path.exists(f[:-6]) else b''
        s0 = (w // 4) ** 2 * 8; s1 = s0 // 4
        m0 = bc1.decode(g[:s0], w, w).reshape(-1, 3).mean(axis=0)
        m2 = bc1.decode(g[s0 + s1:s0 + s1 + s1 // 4], w // 4, w // 4).reshape(-1, 3).mean(axis=0)
        n += 1
        if len(r) >= s0:
            mg = bc1.decode(r[:s0], w, w).reshape(-1, 3).mean(axis=0)
            same = r[:s0] == g[:s0]
        else:
            mg = np.zeros(3); same = None
        bg = np.abs(mg - m2).max() > 12; bm = np.abs(m0 - m2).max() > 12
        badg += bg; badm += bm
        if bg or bm or '-v' in sys.argv:
            print(d, p[1], p[2], w, 'gpu0 %d %d %d guest0 %d %d %d guest2 %d %d %d' % (*mg, *m0, *m2), 'gpu==guest', same, len(r))
    print(d, 'f48 images', n, 'gpu level 0 unlike level 2:', badg, 'guest level 0 unlike level 2:', badm)
