#!/usr/bin/env bash
# OCR a business-directory scan that has no text layer (e.g. CU 1885, 1920): 300 dpi greyscale, Tesseract psm 3, one page per file,
# then join pages with form feeds so the parser sees page breaks.   usage: pipeline/historical/ocr_volume.sh work/hist/pdf/<name>.pdf
set -euo pipefail
pdf="$1"; b=$(basename "$pdf" .pdf); out=work/hist/ocr/$b; mkdir -p "$out" work/hist/text
n=$(pdfinfo "$pdf" | awk '/^Pages/{print $2}')
seq 1 "$n" | xargs -P "${JOBS:-4}" -I{} bash -c '
  p=$(printf "%04d" {}); [ -s "'$out'/p$p.txt" ] && exit 0
  t=$(mktemp -d); pdftoppm -f {} -l {} -r 300 -gray -png "'$pdf'" "$t/pg"
  OMP_THREAD_LIMIT=1 tesseract "$(ls $t/pg*.png | head -1)" "'$out'/p$p" --psm 3 >/dev/null 2>&1; rm -rf "$t"'
python3 - "$out" "work/hist/text/${b}_ocr.txt" <<'PY'
import glob, sys
fs = sorted(glob.glob(sys.argv[1] + '/p*.txt'))
open(sys.argv[2], 'w').write('\f'.join(open(f, errors='ignore').read() for f in fs)); print(len(fs), 'pages ->', sys.argv[2])
PY
