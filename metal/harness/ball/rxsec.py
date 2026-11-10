import struct,sys
def secs(p):
    d=open(p,'rb').read()
    magic,ver,size,n=struct.unpack_from('<4sIII',d,0)
    out=[]
    for i in range(n):
        sid,off,sz,_=struct.unpack_from('<IIII',d,16+16*i)
        out.append((sid,off,sz))
    return d,out
if __name__=='__main__':
    for p in sys.argv[1:]:
        d,s=secs(p)
        print(p.split('/')[-3][:22],p.split('/')[-1],len(d))
        for sid,off,sz in s:
            print('   %08x off %6d size %6d  %s'%(sid,off,sz,d[off:off+24].hex()))
