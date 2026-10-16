"""OCR every directory page with Tesseract (word boxes as TSV) -> work/tsv/<volume>/pNNN.tsv.
The 1999 edition (small type, three narrow columns) is OCR'd column by column -> work/coltxt/DCM_1999/.
Run after extract.py. Tesseract 5.3.4 (eng, LSTM) was used for the published results.

  python pipeline/ocr.py [n_workers]
"""
import os, sys, glob, subprocess
from concurrent.futures import ThreadPoolExecutor
from volumes import VOLUMES

def ocr_page(img):
    d = os.path.basename(os.path.dirname(img)); p = os.path.basename(img)[:-4]
    out = f'work/tsv/{d}/{p}'
    if os.path.exists(out + '.tsv'): return
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run(['tesseract', img, out + '.part', '--psm', '3', 'tsv'], env={**os.environ, 'OMP_THREAD_LIMIT': '1'},
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if os.path.exists(out + '.part.tsv'): os.rename(out + '.part.tsv', out + '.tsv')

if __name__ == '__main__':
    n = int(sys.argv[1]) if len(sys.argv) > 1 else os.cpu_count()
    imgs = [p for v, (_, _, mode) in VOLUMES.items() if mode != 'coltxt' for p in sorted(glob.glob(f'work/img/{v}/p*.png'))]
    with ThreadPoolExecutor(n) as ex: list(ex.map(ocr_page, imgs))
    for v, (_, _, mode) in VOLUMES.items():
        if mode == 'coltxt':
            subprocess.run([sys.executable, 'pipeline/ocr_cols.py', v, '2.5', '3'], check=True)
    print('ocr done')
