# Decode raw BC1/BC3/RGBA8/R8 texture dumps (tex_<addr>_<fmt>_<w>x<h>_t<mode>.bin) to PNG.
import sys, re, numpy as np
from PIL import Image
def c565(c):
    r=((c>>11)&31)*255//31; g=((c>>5)&63)*255//63; b=(c&31)*255//31
    return np.stack([r,g,b],-1).astype(np.int32)
def bc1_color(blk, force4=False):
    c0=blk[:,0].astype(np.uint32)|(blk[:,1].astype(np.uint32)<<8)
    c1=blk[:,2].astype(np.uint32)|(blk[:,3].astype(np.uint32)<<8)
    p0,p1=c565(c0),c565(c1)
    four=(c0>c1)[:,None] | force4
    p2=np.where(four,(2*p0+p1)//3,(p0+p1)//2); p3=np.where(four,(p0+2*p1)//3,0)
    pal=np.stack([p0,p1,p2,p3],1)  # n,4,3
    idx=blk[:,4:8].astype(np.uint32); bits=idx[:,0]|(idx[:,1]<<8)|(idx[:,2]<<16)|(idx[:,3]<<24)
    sel=np.stack([(bits>>(2*i))&3 for i in range(16)],1)
    return np.take_along_axis(pal,sel[:,:,None].repeat(3,2),1)  # n,16,3
def bc3_alpha(blk):
    a0=blk[:,0].astype(np.int32); a1=blk[:,1].astype(np.int32)
    pal=[a0,a1]
    for i in range(1,7):
        pal.append(np.where(a0>a1,((7-i)*a0+i*a1)//7, ((5-i)*a0+i*a1)//5 if i<5 else 0))
    pal[6]=np.where(a0>a1,pal[6],0); pal[7]=np.where(a0>a1,pal[7],255)
    pal=np.stack(pal[:8],1)
    bits=np.zeros(len(blk),np.uint64)
    for i in range(6): bits|=blk[:,2+i].astype(np.uint64)<<np.uint64(8*i)
    sel=np.stack([((bits>>np.uint64(3*i))&np.uint64(7)).astype(np.int64) for i in range(16)],1)
    return np.take_along_axis(pal,sel,1)
for p in sys.argv[1:]:
    m=re.search(r'_([A-Za-z0-9]+)_(\d+)x(\d+)_t',p); fmt,w,h=m.group(1),int(m.group(2)),int(m.group(3))
    d=np.fromfile(p,np.uint8)
    if fmt.startswith('Bc'):
        bw,bh=(w+3)//4,(h+3)//4; bs=8 if fmt.startswith('Bc1') else 16
        blk=d[:bw*bh*bs].reshape(-1,bs)
        if bs==8: rgb=bc1_color(blk); a=np.full(rgb.shape[:2],255)
        elif fmt.startswith('Bc5'):
            r=bc3_alpha(blk[:,:8]); g=bc3_alpha(blk[:,8:])
            rgb=np.stack([r,g,np.full_like(r,128)],-1); a=np.full(r.shape,255)
        else: rgb=bc1_color(blk[:,8:],True); a=bc3_alpha(blk[:,:8])
        img=np.concatenate([rgb,a[:,:,None]],-1).reshape(bh,bw,4,4,4).transpose(0,2,1,3,4).reshape(bh*4,bw*4,4)
        Image.fromarray(img.clip(0,255).astype(np.uint8),'RGBA').convert('RGB').save(p+'.png')
    elif fmt.startswith('R8G8B8A8'):
        Image.fromarray(d[:w*h*4].reshape(h,w,4)).convert('RGB').save(p+'.png')
    elif fmt=='R8Unorm':
        Image.fromarray(d[:w*h].reshape(h,w)).save(p+'.png')
    print(p)
