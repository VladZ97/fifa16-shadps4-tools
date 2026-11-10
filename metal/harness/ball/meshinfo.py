import struct,sys,os,collections
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from rxsec import secs
def mesh(p):
    d,s=secs(p); o={}
    for sid,off,sz in s:
        if sid==0x587aa1:
            size,nv,stride,_=struct.unpack_from('<IIII',d,off); o['nv']=nv; o['stride']=stride; o['v']=d[off+16:off+16+nv*stride]
        if sid==0x5878f4:
            size,ni,isz,_=struct.unpack_from('<IIII',d,off); o['ni']=ni; o['isz']=isz
            o['idx']=struct.unpack_from('<%d%s'%(ni,'H' if isz==2 else 'I'),d,off+16)
        if sid==0xd48d7880: o['prim']=struct.unpack_from('<I',d,off)[0]
        if sid==0xc28193f0: o['decl']=d[off+16:off+sz].split(b'\0')[0].decode()
    return o
if __name__=='__main__':
    c=collections.Counter()
    for p in sys.argv[1:]:
        for f in sorted(os.listdir(p)):
            if f.endswith('.rx3') and 'textures' not in f and not f.startswith('._'):
                m=mesh(os.path.join(p,f)); c[(m.get('prim'),m.get('decl'),m.get('stride'))]+=1
    for k,v in c.items(): print(v,k)
