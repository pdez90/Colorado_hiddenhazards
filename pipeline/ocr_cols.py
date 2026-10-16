import sys, os, glob, subprocess, tempfile, numpy as np
from PIL import Image, ImageFilter
from concurrent.futures import ProcessPoolExecutor
def cols(a):
    dark=(a<140).astype(np.uint8)
    prof=dark[int(a.shape[0]*0.06):].sum(0).astype(float)
    k=np.ones(9)/9; prof=np.convolve(prof,k,'same')
    thr=prof.max()*0.01
    w=a.shape[1]; gaps=[]; i=0
    while i<w:
        if prof[i]<=thr:
            j=i
            while j<w and prof[j]<=thr: j+=1
            if j-i>=max(6,w*0.006) and i>w*0.05 and j<w*0.95: gaps.append((i+j)//2)
            i=j
        else: i+=1
    # merge gaps closer than 12% width
    out=[]
    for g in gaps:
        if not out or g-out[-1]>w*0.12: out.append(g)
    return out
def cols_n(a,n):
    dark=(a<140).astype(np.uint8)
    prof=dark[int(a.shape[0]*0.06):].sum(0).astype(float)
    prof=np.convolve(prof,np.ones(15)/15,'same')
    w=a.shape[1]; # content bounds
    nz=np.where(prof>prof.max()*0.05)[0]; lo,hi=nz[0],nz[-1]
    out=[]
    for k in range(1,n):
        c=lo+(hi-lo)*k/n; r=int((hi-lo)*0.07)
        seg=prof[int(c-r):int(c+r)]
        out.append(int(c-r+np.argmin(seg)))
    return out
NCOL=None
def do(args):
    img,outp,scale=args
    if os.path.exists(outp+'.txt'): return
    im=Image.open(img).convert('L')
    a=np.array(im); cs=cols_n(a,NCOL) if NCOL else cols(a)
    edges=[0]+cs+[a.shape[1]]
    texts=[]
    for k in range(len(edges)-1):
        x0,x1=max(0,edges[k]-3),min(a.shape[1],edges[k+1]+3)
        c=im.crop((x0,0,x1,im.height))
        c=c.resize((int(c.width*scale),int(c.height*scale)),Image.BICUBIC).filter(ImageFilter.UnsharpMask(2,150,2))
        tmp=os.path.join(tempfile.gettempdir(),f'oc_{os.getpid()}.png'); c.save(tmp)
        r=subprocess.run(['tesseract',tmp,'-','--psm','6'],capture_output=True,text=True,env={**os.environ,'OMP_THREAD_LIMIT':'1'})
        texts.append(f'=====COL {k}\n'+r.stdout)
    open(outp+'.txt','w').write('\n'.join(texts))
if __name__=='__main__':
    vol=sys.argv[1]; scale=float(sys.argv[2]) if len(sys.argv)>2 else 2.5
    NCOL=int(sys.argv[3]) if len(sys.argv)>3 else None
    od=f'work/coltxt/{vol}'; os.makedirs(od,exist_ok=True)
    jobs=[(p,f'{od}/'+os.path.basename(p)[:-4],scale) for p in sorted(glob.glob(f'work/img/{vol}/p*.png'))]
    with ProcessPoolExecutor(2) as ex: list(ex.map(do,jobs))
