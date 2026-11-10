# paircheck.py <ball dir> [substitute mesh]: for every ball, the share of the atlas's detailed pixels (level 0 of
# texture 0) that the mesh's UV triangles cover. A mesh made for another panel layout leaves much of the art uncovered.
import sys,os,numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from meshinfo import mesh
from uvcheck import atlas,tris,verts
def cover(mp,tp,N=256):
    m=mesh(mp); a=atlas(tp).astype(np.int32)
    g=a[::a.shape[0]//N,::a.shape[1]//N]
    d=np.abs(np.diff(g,axis=0))[:, :-1].sum(-1)+np.abs(np.diff(g,axis=1))[:-1].sum(-1)
    ink=d>40
    pos,uv=verts(m); im=Image.new('L',(N,N),0); dr=ImageDraw.Draw(im)
    for t in tris(m): dr.polygon([(uv[k][0]*N,uv[k][1]*N) for k in t],fill=255)
    mask=np.array(im)[:-1,:-1]>0
    return (ink&mask).sum()/max(1,ink.sum()), mask.mean(), m['nv']
if __name__=='__main__':
    d=sys.argv[1]; rows=[]
    for f in sorted(os.listdir(d)):
        if f.startswith('._') or not f.endswith('.rx3') or 'textures' in f: continue
        try:
            c,area,nv=cover(os.path.join(d,f),os.path.join(d,f.replace('.rx3','_textures.rx3')))
            s=cover(sys.argv[2],os.path.join(d,f.replace('.rx3','_textures.rx3')))[0] if len(sys.argv)>2 else -1
            rows.append((c,f,area,nv,s))
        except Exception as e: rows.append((-1,f,0,0,-1)); print('ERR',f,e)
    rows.sort()
    for c,f,area,nv,s in rows: print('%-28s cover %.3f uvarea %.3f verts %5d substitute %.3f'%(f,c,area,nv,s))
