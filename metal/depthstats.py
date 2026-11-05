import sys, numpy as np
for p in sys.argv[1:]:
    a=np.fromfile(p, np.float32)
    f=a[np.isfinite(a)]
    print("%s n=%d finite=%.3f min=%.4g p1=%.4g median=%.4g p99=%.4g max=%.4g neg=%.3f" % (p.split('/')[-1][:48], a.size, f.size/max(1,a.size), f.min(), np.percentile(f,1), np.median(f), np.percentile(f,99), f.max(), (f<0).mean()))
