import numpy as np, glob
def f11(v):
    e=(v>>6)&31; m=v&63
    return np.where(e==0, m/64.0*2.0**-14, (1+m/64.0)*2.0**(e.astype(np.float32)-15))
def f10(v):
    e=(v>>5)&31; m=v&31
    return np.where(e==0, m/32.0*2.0**-14, (1+m/32.0)*2.0**(e.astype(np.float32)-15))
def load(n, d='dump2'):
    f=glob.glob(f'{d}/d{n:03d}_*.raw')[0]
    w,h=[int(x) for x in f.split('_')[2].split('x')]
    a=np.fromfile(f,dtype=np.uint32).reshape(h,w)
    return a
def rgb(a):
    return np.stack([f11(a&2047), f11((a>>11)&2047), f10(a>>22)],-1).astype(np.float32)
def tone(c, k=1.0):
    return (np.clip((c*k)/(1+c*k)*1.6,0,1)**(1/2.2)*255).astype(np.uint8)
