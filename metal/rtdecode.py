# Decode raw render target dumps (B10G11R11 / RGBA16F / R16F / R32F / RGBA8 / R8) to PNG, prints mean color.
import sys, re, numpy as np
from PIL import Image
def uf(v, mb):  # unsigned small float, 5-bit exponent
    e=(v>>mb)&31; m=v&((1<<mb)-1)
    return np.where(e==0, m/(1<<mb)*2.0**-14, (1+m/(1<<mb))*2.0**(e.astype(np.float64)-15))
for p in sys.argv[1:]:
    m=re.search(r'_m\d+_([A-Za-z0-9]+)_(\d+)x(\d+)_t',p); fmt,w,h=m.group(1),int(m.group(2)),int(m.group(3))
    if fmt.startswith('B10G11R11'):
        v=np.fromfile(p,np.uint32)[:w*h]
        img=np.stack([uf(v&2047,6),uf((v>>11)&2047,6),uf(v>>22,5)],-1)
    elif fmt=='R16G16B16A16Sfloat': img=np.fromfile(p,np.float16)[:w*h*4].reshape(-1,4)[:,:3].astype(np.float64)
    elif fmt=='R16Sfloat': img=np.fromfile(p,np.float16)[:w*h].astype(np.float64)[:,None].repeat(3,1)
    elif fmt in('R32Sfloat','D32Sfloat'): img=np.fromfile(p,np.float32)[:w*h].astype(np.float64)[:,None].repeat(3,1)
    elif fmt.startswith('R8G8B8A8'): img=np.fromfile(p,np.uint8)[:w*h*4].reshape(-1,4)[:,:3]/255.0
    elif fmt=='R8Unorm': img=np.fromfile(p,np.uint8)[:w*h][:,None].repeat(3,1)/255.0
    else: continue
    img=img.reshape(h,w,3)
    mx=np.percentile(img,99) or 1
    Image.fromarray((np.clip(img/mx,0,1)**(1/2.2)*255).astype(np.uint8)).save(p+'.png')
    print(p.split('/')[-1], 'mean', img.reshape(-1,3).mean(0).round(4), 'p99', round(float(mx),4))
