import os
os.makedirs('work/txtlayer', exist_ok=True)
import pymupdf as fitz, sys, os, glob
src='work/pdf'
for f in sorted(glob.glob(src+'/*.pdf')):
    b=os.path.basename(f)[:-4].replace(' ','_')
    od=f'work/img/{b}'; os.makedirs(od,exist_ok=True)
    d=fitz.open(f)
    for i,p in enumerate(d):
        out=f'{od}/p{i+1:03d}.png'
        if os.path.exists(out): continue
        txt=p.get_text()
        if len(txt.strip())>200:
            open(f'work/txtlayer/{b}_p{i+1:03d}.txt','w').write(txt)
        imgs=sorted(p.get_images(full=True), key=lambda x:-x[2]*x[3])
        try:
            if len(imgs)==1:
                pix=fitz.Pixmap(d,imgs[0][0])
                if pix.alpha: pix=fitz.Pixmap(pix,0)
                if pix.colorspace is None or pix.colorspace.n!=1: pix=fitz.Pixmap(fitz.csGRAY,pix)
            else:
                pix=p.get_pixmap(dpi=200,colorspace=fitz.csGRAY)
        except Exception as e:
            pix=p.get_pixmap(dpi=200,colorspace=fitz.csGRAY)
        pix.save(out)
    print(b, len(d), flush=True)
