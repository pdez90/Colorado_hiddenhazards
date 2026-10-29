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
def line_threshold(W, mh):
    """How close two word centres must be (vertically) to sit on the same printed line. The median word height alone is
    a poor yardstick on low-resolution scans (1992: word boxes ~30 px tall on a 12-16 px line pitch), where it merged
    neighbouring lines and interleaved their words; the 25th-percentile height tracks the x-height and is robust to
    that. (A line-pitch estimate from word tops was tried and rejected: the 1970 layout offsets half-lines, so the
    estimate collapses and split every line.)"""
    hs=[w['h'] for w in W if w['h']>5]
    if not hs: return 0.55*mh
    return max(3.0, 0.55*min(mh,float(np.percentile(hs,25))))

def lines_by_column(W, cuts, mh, thr=None):
    cols=[[] for _ in range(len(cuts)+1)]
    for w in W:
        cx=w['l']+w['w']/2
        k=sum(1 for c in cuts if cx>c)
        cols[k].append(w)
    out=[]
    for ci,ws in enumerate(cols):
        cthr=thr if thr is not None else (line_threshold(ws,mh) if len(ws)>=30 else 0.55*mh)
        ws.sort(key=lambda w:(w['t'],w['l']))
        lines=[]
        for w in ws:
            cy=w['t']+w['h']/2
            if lines and abs(cy-lines[-1]['cy'])<cthr:
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
def adaptive_cuts(W, pw, mh, cands=(3,2)):
    """Pick the column split that leaves the fewest over-long lines. find_columns misses a gutter on 10-30% of the
    1966-1986 pages (words bleeding across a narrow gutter), and a page read as one column interleaves the three
    columns word by word ('4556 TENNYSON 80212 455-4705 DENVER 80223 935-2485'). A directory column is never more
    than ~45 characters wide, so lines longer than that mean merged columns; a cut through text produces 1-2
    character fragments, which count against a forced split."""
    options=[find_columns(W,pw)]+[forced_cuts(W,pw,n) for n in cands if len(W)>=20]
    best=None
    for cuts in options:
        L=lines_by_column(W,cuts,mh)
        score=3*sum(1 for l in L if len(l['text'])>48)+sum(1 for l in L if len(l['text'])<=2)
        if best is None or score<best[0]: best=(score,cuts)
    return best[1]

def page_lines(path, pw=None, ncols=None, adaptive=None):
    """ncols forces that many columns when the gutters are not found; adaptive=(3,2) tries forced 3- and 2-column
    splits against the automatic one and keeps whichever leaves the fewest merged lines (see adaptive_cuts)."""
    W=load_words(path)
    if not W: return [],[]
    if pw is None: pw=max(w['l']+w['w'] for w in W)+5
    hs=[w['h'] for w in W if w['h']>5]; mh=statistics.median(hs) if hs else 20
    # drop giant junk boxes
    W=[w for w in W if w['h']<5*mh]
    if adaptive: cuts=adaptive_cuts(W,pw,mh,adaptive)
    else:
        cuts=find_columns(W,pw)
        if ncols and len(cuts)!=ncols-1: cuts=forced_cuts(W,pw,ncols)
    return lines_by_column(W,cuts,mh),cuts
if __name__=='__main__':
    L,cuts=page_lines(sys.argv[1])
    print('cuts',cuts)
    for l in L: print(f"c{l['col']} {l['y']:5d} {l['x']:5d} | {l['text']}")
