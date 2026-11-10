import glob, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bc1, numpy as np
from PIL import Image
d = sys.argv[1]; addrs = sys.argv[2:-1]; out = sys.argv[-1]
tiles = []
for a in addrs:
    f = glob.glob(d + '/*img3_' + a + '_*f48.raw.guest')[0]
    g = open(f, 'rb').read(); r = open(f[:-6], 'rb').read()
    s0 = 128 * 128 * 8
    tiles.append(bc1.decode(r[:s0], 512, 512))
    tiles.append(bc1.decode(g[:s0], 512, 512))
    l1 = bc1.decode(g[s0:s0 + s0 // 4], 256, 256)
    tiles.append(np.repeat(np.repeat(l1, 2, 0), 2, 1))
Image.fromarray(np.concatenate(tiles, axis=1)).save(out)
