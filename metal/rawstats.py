#!/usr/bin/env python3
# rawstats.py <dir> [n]: per-file float32 statistics of dNNN_*.raw per-draw dumps, in draw order.
import numpy as np,glob,os,re,sys
d=sys.argv[1]; n=int(sys.argv[2]) if len(sys.argv)>2 else 200
files=sorted(glob.glob(d+'/d*.raw'), key=lambda f:int(re.search(r'd(\d+)_',os.path.basename(f)).group(1)))
print(len(files),"files")
for f in files[:n]:
    a=np.fromfile(f,dtype=np.float32); fin=np.isfinite(a); b=a[fin] if fin.any() else a
    print(f"{os.path.basename(f):44s} nonzero {100*(a!=0).mean():5.1f}% min {b.min():.4f} max {b.max():.4f} mean {b.mean():.4f}")
