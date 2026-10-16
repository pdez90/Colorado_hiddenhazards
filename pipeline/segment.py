import csv, sys, os, glob, statistics
import numpy as np
def load_words(path):
    W=[]
    with open(path) as f:
        r=csv.DictReader(f,delimiter='\t',quoting=csv.QUOTE_NONE)
        for x in r:
            if x.get('level')=='5' and x.get('text') and x['text'].strip():
                try:
                    W.append(dict(l=int(x['left']),t=int(x['top']),w=int(x['width']),h=int(x['height']),
                              c=float(x['conf']),s=x['text'].strip()))
                except: pass
    return W
def find_columns(W, pw, mingap=None):
    if not W: return []
    hs=[w['h'] for w in W if w['h']>5]
    mh=statistics.median(hs) if hs else 20
    if mingap is None: mingap=max(12,int(1.2*mh))
    cov=np.zeros(pw+2)
    for w in W:
        if w['h']>4*mh or w['w']>0.6*pw: continue
        cov[max(0,w['l']):min(pw,w['l']+w['w'])]+=1
    # threshold: allow a little noise
    thr=max(1, 0.02*cov.max())
    empty=cov<thr
    # find gaps
    gaps=[];i=0
    while i<pw:
        if empty[i]:
            j=i
            while j<pw and empty[j]: j+=1
            if j-i>=mingap: gaps.append((i,j))
            i=j
        else: i+=1
    # interior gaps only
    xs=[w['l'] for w in W]; xe=[w['l']+w['w'] for w in W]
    lo,hi=np.percentile(xs,1),np.percentile(xe,99)
    cuts=[(a+b)//2 for a,b in gaps if a>lo+0.12*(hi-lo) and b<hi-0.12*(hi-lo)]
    return cuts
def lines_by_column(W, cuts, mh):
    cols=[[] for _ in range(len(cuts)+1)]
    for w in W:
        cx=w['l']+w['w']/2
        k=sum(1 for c in cuts if cx>c)
        cols[k].append(w)
    out=[]
    for ci,ws in enumerate(cols):
        ws.sort(key=lambda w:(w['t'],w['l']))
        lines=[]
        for w in ws:
            cy=w['t']+w['h']/2
            if lines and abs(cy-lines[-1]['cy'])<0.55*mh:
                L=lines[-1]; L['ws'].append(w); L['cy']=(L['cy']*(len(L['ws'])-1)+cy)/len(L['ws'])
            else:
                lines.append(dict(cy=cy,ws=[w]))
        for L in lines:
            L['ws'].sort(key=lambda w:w['l'])
            out.append(dict(col=ci,y=int(L['cy']),x=L['ws'][0]['l'],text=' '.join(w['s'] for w in L['ws']),
                            conf=float(np.mean([w['c'] for w in L['ws']]))))
    return out
def forced_cuts(W,pw,n):
    cov=np.zeros(pw+2)
    for w in W: cov[max(0,w['l']):min(pw,w['l']+w['w'])]+=1
    xs=[w['l'] for w in W]; xe=[w['l']+w['w'] for w in W]
    lo,hi=np.percentile(xs,0.5),np.percentile(xe,99.5)
    cuts=[]
    for k in range(1,n):
        c=lo+(hi-lo)*k/n; r=(hi-lo)*0.07
        a,b=int(c-r),int(c+r)
        seg=cov[a:b]; cuts.append(a+int(np.argmin(seg)))
    return cuts
def page_lines(path, pw=None, ncols=None):
    W=load_words(path)
    if not W: return [],[]
    if pw is None: pw=max(w['l']+w['w'] for w in W)+5
    hs=[w['h'] for w in W if w['h']>5]; mh=statistics.median(hs) if hs else 20
    # drop giant junk boxes
    W=[w for w in W if w['h']<5*mh]
    cuts=find_columns(W,pw)
    if ncols and len(cuts)!=ncols-1: cuts=forced_cuts(W,pw,ncols)
    return lines_by_column(W,cuts,mh),cuts
if __name__=='__main__':
    L,cuts=page_lines(sys.argv[1])
    print('cuts',cuts)
    for l in L: print(f"c{l['col']} {l['y']:5d} {l['x']:5d} | {l['text']}")
