# uvcheck.py <mesh.rx3> <textures.rx3> <out.png>: the mesh's UV triangles drawn over the atlas (level 0 of texture 0),
# plus a flat-shaded orthographic software render of the textured ball (front view) beside it.
import struct,sys,os,numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from meshinfo import mesh
from rxsec import secs
def bc1(d,w,h):
    blk=np.frombuffer(d[:w*h//2],np.uint8).reshape(-1,8)
    c0=blk[:,0].astype(np.uint32)|(blk[:,1].astype(np.uint32)<<8); c1=blk[:,2].astype(np.uint32)|(blk[:,3].astype(np.uint32)<<8)
    def c565(c): return np.stack([((c>>11)&31)*255//31,((c>>5)&63)*255//63,(c&31)*255//31],-1).astype(np.int32)
    p0,p1=c565(c0),c565(c1); four=(c0>c1)[:,None]
    p2=np.where(four,(2*p0+p1)//3,(p0+p1)//2); p3=np.where(four,(p0+2*p1)//3,0)
    pal=np.stack([p0,p1,p2,p3],1)
    bits=blk[:,4].astype(np.uint32)|(blk[:,5].astype(np.uint32)<<8)|(blk[:,6].astype(np.uint32)<<16)|(blk[:,7].astype(np.uint32)<<24)
    sel=np.stack([(bits>>(2*i))&3 for i in range(16)],1)
    px=np.take_along_axis(pal,sel[:,:,None].repeat(3,2),1).reshape(h//4,w//4,4,4,3).transpose(0,2,1,3,4).reshape(h,w,3)
    return px.astype(np.uint8)
def atlas(p):
    d,s=secs(p)
    off=[o for sid,o,sz in s if sid==0x7a0b60da][0]
    size,_,_,_,w,h,_,mips=struct.unpack_from('<IBBHHHHH',d,off)
    return bc1(d[off+16:],w,h)
def tris(m):
    i=m['idx']
    if m['prim']==4: return [(i[k],i[k+1],i[k+2]) for k in range(0,len(i)-2,3)]
    out=[]
    for k in range(len(i)-2):
        a,b,c=i[k],i[k+1],i[k+2]
        if a==b or b==c or a==c: continue
        out.append((a,b,c) if k%2==0 else (b,a,c))
    return out
def verts(m):
    st=m['stride']; v=np.frombuffer(m['v'],np.uint8).reshape(-1,st)
    if '3f32' in m['decl'].split()[0]:
        pos=v[:,:12].copy().view('<f4').reshape(-1,3).astype(np.float64); uvo=20
    else:
        pos=v[:,:8].copy().view('<f2').reshape(-1,4)[:,:3].astype(np.float64); uvo=16
    uv=v[:,uvo:uvo+4].copy().view('<f2').reshape(-1,2).astype(np.float64)
    return pos,uv
if __name__=='__main__':
    m=mesh(sys.argv[1]); a=atlas(sys.argv[2]); H,W=a.shape[:2]
    pos,uv=verts(m); T=tris(m)
    print(os.path.basename(sys.argv[1]),'verts',m['nv'],'tris',len(T),'uv min',uv.min(0).round(3),'max',uv.max(0).round(3),'atlas',W,H)
    im=Image.fromarray(a).convert('RGB'); dr=ImageDraw.Draw(im)
    for t in T:
        pts=[(uv[k][0]*W,uv[k][1]*H) for k in t]; dr.line(pts+[pts[0]],fill=(255,0,255),width=1)
    # software render: orthographic along -z, z-buffer, per-pixel uv
    R=512; c=pos.mean(0); r=np.abs(pos-c).max()*1.05
    img=np.zeros((R,R,3),np.uint8); zb=np.full((R,R),-1e9)
    P=(pos-c)/r
    for t in T:
        p=P[list(t)]; u=uv[list(t)]
        x=(p[:,0]*0.5+0.5)*R; y=(0.5-p[:,1]*0.5)*R; z=p[:,2]
        x0,x1=int(max(0,np.floor(x.min()))),int(min(R-1,np.ceil(x.max()))); y0,y1=int(max(0,np.floor(y.min()))),int(min(R-1,np.ceil(y.max())))
        if x1<x0 or y1<y0: continue
        den=(y[1]-y[2])*(x[0]-x[2])+(x[2]-x[1])*(y[0]-y[2])
        if abs(den)<1e-9: continue
        gx,gy=np.meshgrid(np.arange(x0,x1+1)+0.5,np.arange(y0,y1+1)+0.5)
        w0=((y[1]-y[2])*(gx-x[2])+(x[2]-x[1])*(gy-y[2]))/den; w1=((y[2]-y[0])*(gx-x[2])+(x[0]-x[2])*(gy-y[2]))/den; w2=1-w0-w1
        ins=(w0>=0)&(w1>=0)&(w2>=0)
        zz=w0*z[0]+w1*z[1]+w2*z[2]
        sub=zb[y0:y1+1,x0:x1+1]; ok=ins&(zz>sub)
        if not ok.any(): continue
        uu=(w0*u[0,0]+w1*u[1,0]+w2*u[2,0]); vv=(w0*u[0,1]+w1*u[1,1]+w2*u[2,1])
        tx=(np.floor(uu*W).astype(int))%W; ty=(np.floor(vv*H).astype(int))%H
        sub[ok]=zz[ok]; img[y0:y1+1,x0:x1+1][ok]=a[ty[ok],tx[ok]]
    out=Image.new('RGB',(512*2,512)); out.paste(im.resize((512,512),Image.LANCZOS),(0,0)); out.paste(Image.fromarray(img),(512,0)); out.save(sys.argv[3])
