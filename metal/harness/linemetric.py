import sys, numpy as np
from PIL import Image
# linemetric.py <png> x0 y0 x1 y1 : follows a white pitch line between two approximate points and reports, for its
# far (top) and near (bottom) edges, the RMS distance in display pixels of the half-intensity crossing from a straight
# fit (a smooth anti-aliased edge stays well under 0.3, stair-steps of 2 source pixels read about 0.8-1.0).
f,x0,y0,x1,y1=sys.argv[1],*map(float,sys.argv[2:6])
im=np.asarray(Image.open(f).convert('RGB'),dtype=np.float32)
w=im.min(axis=2)  # white = all channels high; grass has low blue/red
xs=np.arange(int(x0),int(x1)); top=[]; bot=[]; cols=[]
for x in xs:
    yc=y0+(y1-y0)*(x-x0)/(x1-x0)
    a=int(yc-14); col=w[a:a+29,int(x)]
    g=np.percentile(col,20); p=col.max()
    if p-g<40: continue
    h=(g+p)/2; idx=np.where(col>=h)[0]
    if len(idx)==0: continue
    i=idx[0]; j=idx[-1]
    if i==0 or j==len(col)-1: continue
    t=i-1+(h-col[i-1])/(col[i]-col[i-1]); b=j+(col[j]-h)/(col[j]-col[j+1])
    top.append(a+t); bot.append(a+b); cols.append(x)
cols=np.array(cols); out=[]
for name,v in (('far',np.array(top)),('near',np.array(bot))):
    xc=cols-cols.mean(); c=np.polyfit(xc,v,1); r=v-np.polyval(c,xc)
    keep=np.abs(r)<2.5; c=np.polyfit(xc[keep],v[keep],1); r=(v-np.polyval(c,xc))[keep]
    out.append(f"{name} edge rms {np.sqrt((r**2).mean()):.2f} px, max {np.abs(r).max():.2f}")
print(f.split('/')[-1], f"{len(cols)} columns:", '; '.join(out), f"; mean width {np.mean(np.array(bot)-np.array(top)):.1f} px")
