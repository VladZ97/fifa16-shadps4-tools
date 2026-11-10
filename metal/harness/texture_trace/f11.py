import sys,struct,zlib
import numpy as np
def dec(path,w,h):
    a=np.fromfile(path,dtype='<u4')[:w*h].reshape(h,w)
    def uf(v,mb):
        e=(v>>mb)&31; m=v&((1<<mb)-1)
        return np.where(e==0, m/float(1<<mb)*2.0**-14, (1+m/float(1<<mb))*2.0**(e.astype(np.float64)-15))
    r=uf(a&0x7ff,6); g=uf((a>>11)&0x7ff,6); b=uf((a>>22)&0x3ff,5)
    return a,np.stack([r,g,b],-1)
def png(path,img):
    h,w,_=img.shape
    raw=b''.join(b'\x00'+img[y].tobytes() for y in range(h))
    def ch(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    open(path,'wb').write(b'\x89PNG\r\n\x1a\n'+ch(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+ch(b'IDAT',zlib.compress(raw))+ch(b'IEND',b''))
base=sys.argv[1]; w=int(sys.argv[2]); h=int(sys.argv[3])
ag,g=dec(base+'.gpu0',w,h); au,u=dec(base+'.guest',w,h)
print('texels differ',int((ag!=au).sum()),'of',w*h)
print('gpu0 mean rgb',g.reshape(-1,3).mean(0).round(4),'max',g.max().round(3),'zero texels',int((ag==0).sum()))
print('guest mean rgb',u.reshape(-1,3).mean(0).round(4),'max',u.max().round(3),'zero texels',int((au==0).sum()))
d=np.abs(g-u).reshape(-1,3); print('mean abs diff',d.mean(0).round(4),'max',d.max().round(3))
rows=(ag!=au).any(1); cols=(ag!=au).any(0)
print('rows changed',int(rows.sum()),'cols changed',int(cols.sum()))
m=max(g.max(),u.max(),1e-6)
for n,x in (('gpu0',g),('guest',u)):
    y=np.clip((x/m)**(1/2.2)*255,0,255).astype(np.uint8)
    y=np.repeat(y,2,0)
    png(sys.argv[4]+'_'+n+'.png',y)
